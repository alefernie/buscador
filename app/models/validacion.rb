# Modelo sin tabla, solo para automatizar la validacion de archivos excel
class Validacion < ActiveRecord::Base

  belongs_to :usuario

  COLUMNAS_OPCIONALES = %w(reino division subdivision clase subclase orden suborden infraorden superfamilia autoridad_infraespecie)
  COLUMNAS_OBLIGATORIAS = %w(familia genero especie autoridad infraespecie categoria nombre_cientifico)
  FORMATOS_PERMITIDOS_BATCH = %w(text/csv)

  # Valida el taxon cuando solo pasan el nombre cientifico
  def valida_batch(path)
    sleep(30)  # Es necesario el sleep ya que trata de leer el archivo antes de que lo haya escrito en disco
    @hash = []
    lineas = File.open(path).read

    lineas.each_line do |linea|
      info = encuentra_record_por_nombre_cientifico_csv(linea.limpia)
      @hash << asocia_respuesta_csv(info)
    end  # Fin each do lineas

    escribe_excel_csv
    EnviaCorreo.excel(self).deliver
  end

  def encuentra_record_por_nombre_cientifico_csv(linea)
    # Evita que el nombre cientifico este vacio
    if linea.blank?
      return {estatus: false, linea: linea, error: 'El nombre cientifico está vacío'}
    end

    taxon = Especie.where(:nombre_cientifico => linea)

    if taxon.length == 1  # Caso mas sencillo, coincide al 100 y solo es uno
      taxon = asigna_categorias_correspondientes(taxon.first)
      return {taxon: taxon, linea: linea, estatus: true}

    elsif taxon.length > 1  # Encontro el mismo nombre cientifico mas de una vez
      # Mando a imprimir solo el valido
      taxon.each do |t|
        if t.estatus == 2
          tax = asigna_categorias_correspondientes(t)
          return {taxon: tax, linea: linea, estatus: true}
        end
      end

      return busca_recursivamente_csv(taxon, linea)

    else
      # Parte de expresiones regulares a ver si encuentra alguna coincidencia
      nombres = linea.split(' ')

      taxon = if nombres.length == 2  # Especie
                Especie.where("nombre_cientifico LIKE '#{nombres[0]} % #{nombres[1]}'")
              elsif nombres.length == 3  # Infraespecie
                Especie.where("nombre_cientifico LIKE '#{nombres[0]} % #{nombres[1]} % #{nombres[2]}'")
              elsif nombres.length == 1 # Genero o superior
                Especie.where("nombre_cientifico LIKE '#{nombres[0]}'")
              end

      if taxon.present? && taxon.length == 1  # Caso mas sencillo
        taxon = asigna_categorias_correspondientes(taxon.first)
        return {taxon: taxon, linea: linea, estatus: true}
      elsif taxon.present? && taxon.length > 1
        return busca_recursivamente_csv(taxon, linea)
      else  # Lo buscamos con el fuzzy match y despues con el algoritmo de aproximacion
        ids = FUZZY_NOM_CIEN.find(linea, limit=CONFIG.limit_fuzzy)

        if ids.present?
          taxones = Especie.caso_rango_valores('especies.id', ids.join(','))

          if taxones.empty?
            return {estatus: false, linea: linea, error: 'Sin coincidencias'}
          end

          taxones_con_distancia = []
          taxones.each do |taxon|
            # Si la distancia entre palabras es menor a 3 que muestre la sugerencia
            distancia = Levenshtein.distance(linea.downcase, taxon.nombre_cientifico.limpiar.downcase)

            if distancia == 0  # Es exactamente el mismo taxon
              t = asigna_categorias_correspondientes(taxon)
              return {taxon: t, linea: linea, estatus: true}
            end

            next if distancia > 2  # No cumple con la distancia
            taxones_con_distancia << taxon
          end

          if taxones_con_distancia.empty?
            return {estatus: false, linea: linea, error: 'Sin coincidencias'}
          else
            return busca_recursivamente_csv(taxones_con_distancia, linea)
          end

        else  # No hubo coincidencias con su nombre cientifico
          return {estatus: false, linea: linea, error: 'Sin coincidencias'}
        end
      end

    end  #Fin de las posibles coincidencias
  end

  # Si concidio mas de uno, busca recursivamente arriba de genero (familia) para ver el indicado
  def busca_recursivamente_csv(taxones, linea)
    taxon_coincidente = Especie.none
    nombres = linea.split(' ')

    taxones_coincidentes = taxones.map{|t| asigna_categorias_correspondientes(t)}
    taxones_coincidentes.each do |t|  # Iterare cada taxon que resulto parecido para ver cual es el correcto
      t = asigna_categorias_correspondientes(t)
      next unless t.present?  # Por si regresa nulo

      # Si es la especie lo mando directo a coincidencia
      cat_tax_taxon_cat = I18n.transliterate(t.x_categoria_taxonomica).gsub(' ','_').downcase
      if cat_tax_taxon_cat == 'especie' && nombres.length == 2
        return {taxon: t, estatus: true, linea: linea, info: "Posibles coincidencias: #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
      end

      # Si no coincidio con ninguno le dejo el unico
      if taxones.length == 1
        return {taxon: t, estatus: true, linea: linea, info: "Posibles coincidencias: #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
      end

      return {estatus: false, linea: linea, error: "Posibles coincidencias: #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
    end  #Fin each taxones coincidentes
  end

  # Asocia la respuesta para armar el contenido del excel
  def asocia_respuesta_csv(info = {})
    columna_resumen = Hash.new

    if info[:estatus]
      taxon = info[:taxon]

      if taxon.estatus == 1  # Si es sinonimo, asocia el nombre_cientifico valido
        estatus = taxon.especies_estatus     # Checa si existe alguna sinonimia

        if estatus.length == 1  # Encontro el valido y solo es uno, como se esperaba
          begin  # Por si ya no existe ese taxon, suele pasar!
            taxon_valido = Especie.find(estatus.first.especie_id2)
            t_val = asigna_categorias_correspondientes(taxon_valido)  # Le asociamos los datos
            info[:taxon_valido] = t_val
          rescue
            info[:estatus] = false
            info[:error] = 'No existe el taxón válido en CAT'
          end

        else  # No existe el valido >.>!
          info[:estatus] = false
          info[:error] = 'No existe el taxón válido en CAT'
        end
      end  # End estatus = 1

      columna_resumen['SCAT_Observaciones'] = "Información: #{info[:info]}" if info[:info].present?

    else
      columna_resumen['SCAT_Observaciones'] = "Revisión: #{info[:error]}" if info[:error].present?
    end  # End info estatus

    # Se completa la seccion del excel en respuesta
    {nombre_cientifico: info[:linea]}.merge(validacion_interna(info)).merge(columna_resumen)
  end

  # Escribe los datos del excel con la gema rubyXL
  def escribe_excel_csv
    xlsx = RubyXL::Workbook.new
    sheet = xlsx[0]
    sheet.sheet_name = 'Validacion_CONABIO'
    fila = 1  # Uno para que 0 sea la cabecera

    @hash.each do |h|
      columna = 0  # Desde la columna donde empieza

      h.each do |k,v|

        # Para la cabecera
        sheet.add_cell(0,columna,k) if fila == 1

        # Para los demas datos
        sheet.add_cell(fila,columna,v)
        columna+= 1
      end
      fila+= 1
    end

    # Escribe el excel en cierta ruta
    ruta_excel = Rails.root.join('public','validaciones_excel', usuario_id.to_s)
    FileUtils.mkpath(ruta_excel, :mode => 0755) unless File.exists?(ruta_excel)
    puts "#{ruta_excel.to_s}/#{nombre_archivo}.xlsx"
    xlsx.write("#{ruta_excel.to_s}/#{nombre_archivo}.xlsx")
  end

  ###############################################
  # Parte de la validacion del excel
  ###############################################
  # Escribe los datos del excel con la gema rubyXL
  def escribe_excel(path)
    xlsx = RubyXL::Parser.parse(path)  # El excel con su primera sheet
    sheet = xlsx[0]
    fila = 1  # Empezamos por la cabecera

    @hash.each do |h|
      columna = @sheet.last_column  # Desde la columna donde empieza

      h.each do |k,v|
        next if COLUMNAS_OPCIONALES.include?(k) || COLUMNAS_OBLIGATORIAS.include?(k)

        # Para la cabecera
        sheet.add_cell(0,columna,k) if fila == 1

        # Para los demas datos
        sheet.add_cell(fila,columna,v)
        columna+= 1
      end
      fila+= 1
    end

    # Escribe el excel en cierta ruta
    ruta_excel = Rails.root.join('public','validaciones_excel', usuario_id.to_s)
    FileUtils.mkpath(ruta_excel, :mode => 0755) unless File.exists?(ruta_excel)
    xlsx.write("#{ruta_excel.to_s}/#{nombre_archivo}.xlsx")
    puts "Escribio excel en: #{ruta_excel.to_s}/#{nombre_archivo}.xlsx"
  end

  def asigna_categorias_correspondientes(taxon)
    return nil unless taxon.ancestry_ascendente_directo.present?  # Por si se les olvido poner el ascendente_directo o es reino
    ids = taxon.ancestry_ascendente_directo.gsub('/',',')

    Especie.select('nombre, nombre_categoria_taxonomica').categoria_taxonomica_join.caso_rango_valores('especies.id',ids).each do |ancestro|
      categoria = 'x_' << I18n.transliterate(ancestro.nombre_categoria_taxonomica).gsub(' ','_').downcase
      next unless Lista::COLUMNAS_CATEGORIAS.include?(categoria)
      eval("taxon.#{categoria} = ancestro.nombre")  # Asigna el nombre del ancestro si es que coincidio con la categoria

      # Asigna autoridades para el excel
      if categoria == 'x_especie'
        taxon.x_nombre_autoridad_especie = taxon.nombre_autoridad
      end

      # Para las infraespecies
      infraespecies = CategoriaTaxonomica::CATEGORIAS_INFRAESPECIES.map{|c| "x_#{c}"}
      if infraespecies.include?(categoria)
        taxon.x_nombre_autoridad_infraespecie = taxon.nombre_autoridad
      end
    end

    # Asigna la categoria taxonomica
    taxon.x_categoria_taxonomica = taxon.categoria_taxonomica.nombre_categoria_taxonomica
    taxon
  end

  # Si concidio mas de uno, busca recursivamente el indicado
  def busca_recursivamente(taxones, hash)
    coincidio_alguno = false
    taxon_coincidente = Especie.none
    nombres = hash['nombre_cientifico'].split(' ')
    h = hash

    taxones_coincidentes = taxones.map{|t| asigna_categorias_correspondientes(t)}
    taxones_coincidentes.each do |t|  # Iterare cada taxon que resulto parecido para ver cual es el correcto
      t = asigna_categorias_correspondientes(t)
      next unless t.present?  # Por si regresa nulo

      # Si es la especie lo mando directo a coincidencia
      cat_tax_taxon_cat = I18n.transliterate(t.x_categoria_taxonomica).gsub(' ','_').downcase
      if cat_tax_taxon_cat == 'especie' && nombres.length == 2 && hash['infraespecie'].blank?
        return {taxon: t, hash: h, estatus: true, info: "Posibles coincidencias: #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
      end

      # Caso para infraespecies
      variedad = %w(var. var variedad)
      if cat_tax_taxon_cat == 'variedad' && nombres.length == 3 && variedad.include?(hash['categoria'].try(:downcase))
        return {taxon: t, hash: h, estatus: true, info: "Posibles coincidencias: #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
      end

      subvariedad = %w(subvar. subvar subvariedad)
      if cat_tax_taxon_cat == 'subvariedad' && nombres.length == 3 && subvariedad.include?(hash['categoria'].try(:downcase))
        return {taxon: t, hash: h, estatus: true, info: "Posibles coincidencias: #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
      end

      forma = %w(f. f forma)
      if cat_tax_taxon_cat == 'forma' && nombres.length == 3 && forma.include?(hash['categoria'].try(:downcase))
        return {taxon: t, hash: h, estatus: true, info: "Posibles coincidencias: #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
      end

      subforma = %w(subf. subf subforma)
      if cat_tax_taxon_cat == 'subforma' && nombres.length == 3 && subforma.include?(hash['categoria'].try(:downcase))
        return {taxon: t, hash: h, estatus: true, info: "Posibles coincidencias: #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
      end

      # Si no coincide ninguna de las infraespecies anteriores, toma subespecie por default
      subespecies = %w(subsp. subsp subespecie ssp. ssp)
      if cat_tax_taxon_cat == 'subespecie' && nombres.length == 3 && (hash['categoria'].blank? || subespecies.include?(hash['categoria'].try(:downcase)))
        return {taxon: t, hash: h, estatus: true, info: "Posibles coincidencias: #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
      end

      # Para poner el genero si esque esta vacio con especie
      if cat_tax_taxon_cat == 'genero' && nombres.length == 1 && hash['especie'].blank?
        return {taxon: t, hash: h, estatus: true, info: "Posibles coincidencias: (validó hasta género) #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
      end

      # Si no coincidio con ninguno le dejo el unico
      if taxones.length == 1
        return {taxon: t, hash: h, estatus: true, info: "Posibles coincidencias: #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
      end

      # Comparamos entonces la familia, si vuelve a coincidir seguro existe un error en catalogos
      if t.x_familia == hash['familia'].try(:downcase)

        if coincidio_alguno
          return {hash: h, estatus: false, error: "Posibles coincidencias: #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
        else
          taxon_coincidente = t
          coincidio_alguno = true
        end
      end
    end  #Fin each taxones coincidentes

    # Mando el taxon si coincidio alguno
    if coincidio_alguno
      return {taxon: taxon_coincidente, hash: h, estatus: true}
    else  # De lo contrario no hubo coincidencias claras
      return {hash: h, estatus: false, error: "Posibles coincidencias: #{taxones_coincidentes.map{|t_c| "#{t_c.x_categoria_taxonomica} #{t_c.nombre_cientifico}"}.join(', ')}"}
    end
  end

  # Encuentra el mas parecido
  def encuentra_record_por_nombre_cientifico(hash = {})
    # Evita que el nombre cientifico este vacio
    if hash['nombre_cientifico'].blank?
      return {hash: hash, estatus: false, error: 'El nombre cientifico está vacío'}
    end

    h = hash
    taxon = Especie.where(nombre_cientifico: hash['nombre_cientifico'].strip)

    if taxon.length == 1  # Caso mas sencillo, coincide al 100 y solo es uno
      taxon = asigna_categorias_correspondientes(taxon.first)
      return {taxon: taxon, hash: hash, estatus: true}

    elsif taxon.length > 1  # Encontro el mismo nombre cientifico mas de una vez
      # Mando a imprimir solo el valido
      taxon.each do |t|
        if t.estatus == 2
          tax = asigna_categorias_correspondientes(t)
          return {taxon: tax, hash: hash, estatus: true}
        end
      end

      return busca_recursivamente(taxon, hash)

    else
      # Parte de expresiones regulares a ver si encuentra alguna coincidencia
      nombres = hash['nombre_cientifico'].strip.split(' ')

      taxon = if nombres.length == 2  # Especie
                Especie.where("nombre_cientifico LIKE '#{nombres[0]} % #{nombres[1]}'")
              elsif nombres.length == 3  # Infraespecie
                Especie.where("nombre_cientifico LIKE '#{nombres[0]} % #{nombres[1]} % #{nombres[2]}'")
              elsif nombres.length == 1 # Genero o superior
                Especie.where("nombre_cientifico LIKE '#{nombres[0]}'")
              end

      if taxon.present? && taxon.length == 1  # Caso mas sencillo
        taxon = asigna_categorias_correspondientes(taxon.first)
        return {taxon: taxon, hash: hash, estatus: true}
      elsif taxon.present? && taxon.length > 1
        return busca_recursivamente(taxon, hash)
      else  # Lo buscamos con el fuzzy match y despues con el algoritmo de aproximacion
        ids = FUZZY_NOM_CIEN.find(hash['nombre_cientifico'].strip, limit=CONFIG.limit_fuzzy)

        if ids.present?
          taxones = Especie.caso_rango_valores('especies.id', ids.join(','))
          return {hash: h, estatus: false, error: 'Sin coincidencias'} if taxones.empty?
          taxones_con_distancia = []

          taxones.each do |taxon|
            # Si la distancia entre palabras es menor a 3 que muestre la sugerencia
            distancia = Levenshtein.distance(hash['nombre_cientifico'].strip.downcase, taxon.nombre_cientifico.strip.limpiar.downcase)

            if distancia == 0  # Es exactamente el mismo taxon
              t = asigna_categorias_correspondientes(taxon)
              return {taxon: t, hash: hash, estatus: true}
            end

            next if distancia > 2  # No cumple con la distancia
            taxones_con_distancia << taxon
          end

          if taxones_con_distancia.empty?
            return {hash: h, estatus: false, error: 'Sin coincidencias'}
          else
            return busca_recursivamente(taxones_con_distancia, hash)
          end

        else  # No hubo coincidencias con su nombre cientifico
          return {hash: h, estatus: false, error: 'Sin coincidencias'}
        end
      end

    end  #Fin de las posibles coincidencias
  end

  def valida_campos(path, asociacion)
    sleep(30)  # Es necesario el sleep ya que trata de leer el archivo antes de que lo haya escrito en disco
    @hash = []
    primera_fila = true

    xlsx = Roo::Excelx.new(path, packed: nil, file_warning: :ignore)
    @sheet = xlsx.sheet(0)  # toma la primera hoja por default

    #sheet.parse(:clean => true)  # Para limpiar los caracteres de control y espacios en blanco de mas
    @sheet.parse(asociacion).each do |hash|
      if primera_fila
        primera_fila = false
        next
      end

      info = encuentra_record_por_nombre_cientifico(hash)
      @hash << asocia_respuesta(info)
    end

    escribe_excel(path)
    EnviaCorreo.excel(self).deliver
  end

  # Asocia la respuesta para armar el contenido del excel
  def asocia_respuesta(info = {})
    if info[:estatus]
      taxon = info[:taxon]

      if taxon.estatus == 1  # Si es sinonimo, asocia el nombre_cientifico valido
        estatus = taxon.especies_estatus     # Checa si existe alguna sinonimia

        if estatus.length == 1  # Encontro el valido y solo es uno, como se esperaba
          begin  # Por si ya no existe ese taxon, suele pasar!
            taxon_valido = Especie.find(estatus.first.especie_id2)
            t_val = asigna_categorias_correspondientes(taxon_valido)  # Le asociamos los datos
            info[:taxon_valido] = t_val
          rescue
            info[:estatus] = false
            info[:error] = 'No existe el taxón válido en CAT'
          end

        else  # No existe el valido >.>!
          info[:estatus] = false
          info[:error] = 'No existe el taxón válido en CAT'
        end
      end  # End estatus = 1
    end  # End info estatus

    # Se completa cada seccion del excel
    resumen_hash = resumen(info)
    correcciones_hash = correcciones(info)
    validacion_interna_hash = validacion_interna(info)

    # Devuelve toda la asociacion unida y en orden
    info[:hash].merge(resumen_hash).merge(correcciones_hash).merge(validacion_interna_hash)
  end

  # Parte roja del excel
  def resumen(info = {})
    resumen_hash = {}

    if info[:estatus]
      taxon = info[:taxon]
      hash = info[:hash]

      resumen_hash['SCAT_NombreEstatus'] = Especie::ESTATUS_SIGNIFICADO[taxon.estatus]

      if info[:info].present?
        resumen_hash['SCAT_Observaciones'] = "Información: #{info[:info]}"
      else
        resumen_hash['SCAT_Observaciones'] = nil
      end

      resumen_hash['SCAT_Correccion_NombreCient'] = taxon.nombre_cientifico.downcase == hash['nombre_cientifico'].downcase ? nil : taxon.nombre_cientifico
      resumen_hash['SCAT_NombreCient_valido'] = info[:taxon_valido].present? ? info[:taxon_valido].nombre_cientifico : taxon.nombre_cientifico
      resumen_hash['SCAT_Autoridad_NombreCient_valido'] = info[:taxon_valido].present? ? info[:taxon_valido].nombre_autoridad : taxon.nombre_autoridad

    else  # Asociacion vacia, solo el error
      resumen_hash['SCAT_NombreEstatus'] = nil

      if info[:error].present?
        resumen_hash['SCAT_Observaciones'] = "Revisión: #{info[:error]}"
      else
        resumen_hash['SCAT_Observaciones'] = nil
      end

      resumen_hash['SCAT_Correccion_NombreCient'] = nil
      resumen_hash['SCAT_NombreCient_valido'] = nil
      resumen_hash['SCAT_Autoridad_NombreCient_valido'] = nil
    end

    resumen_hash
  end

  # Parte azul del excel
  def correcciones(info = {})
    correcciones_hash = {}
    hash = info[:hash]

    if info[:estatus]
      taxon = info[:taxon]

      if hash.key?('reino')
        correcciones_hash['SCAT_CorreccionReino'] = taxon.x_reino.try(:downcase) == hash['reino'].try(:downcase) ? nil : taxon.x_reino
      end

      if hash.key?('division')
        correcciones_hash['SCAT_CorreccionDivision'] = taxon.x_division.try(:downcase) == hash['division'].try(:downcase) ? nil : taxon.x_division
      end

      if hash.key?('subdivision')
        correcciones_hash['SCAT_CorreccionSubdivision'] = taxon.x_subdivision.try(:downcase) == hash['subdivision'].try(:downcase) ? nil : taxon.x_subdivision
      end

      if hash.key?('phylum')
        correcciones_hash['SCAT_CorreccionPhylum'] = taxon.x_phylum.try(:downcase) == hash['phylum'].try(:downcase) ? nil : taxon.x_phylum
      end

      if hash.key?('clase')
        correcciones_hash['SCAT_CorreccionClase'] = taxon.x_clase.try(:downcase) == hash['clase'].try(:downcase) ? nil : taxon.x_clase
      end

      if hash.key?('subclase')
        correcciones_hash['SCAT_CorreccionSubclase'] = taxon.x_subclase.try(:downcase) == hash['subclase'].try(:downcase) ? nil : taxon.x_subclase
      end

      if hash.key?('orden')
        correcciones_hash['SCAT_CorreccionOrden'] = taxon.x_orden.try(:downcase) == hash['orden'].try(:downcase) ? nil : taxon.x_orden
      end

      if hash.key?('suborden')
        correcciones_hash['SCAT_CorreccionSuborden'] = taxon.x_suborden.try(:downcase) == hash['suborden'].try(:downcase) ? nil : taxon.x_suborden
      end

      if hash.key?('infraorden')
        correcciones_hash['SCAT_CorreccionInfraorden'] = taxon.x_infraorden.try(:downcase) == hash['infraorden'].try(:downcase) ? nil : taxon.x_infraorden
      end

      if hash.key?('superfamilia')
        correcciones_hash['SCAT_CorreccionSuperfamilia'] = taxon.x_superfamilia.try(:downcase) == hash['superfamilia'].try(:downcase) ? nil : taxon.x_superfamilia
      end

      if hash.key?('familia')
        correcciones_hash['SCAT_CorreccionFamilia'] = taxon.x_familia.try(:downcase) == hash['familia'].try(:downcase) ? nil : taxon.x_familia
      end

      if hash.key?('genero')
        correcciones_hash['SCAT_CorreccionGenero'] = taxon.x_genero.try(:downcase) == hash['genero'].try(:downcase) ? nil : taxon.x_genero
      end

      if hash.key?('subgenero')
        correcciones_hash['SCAT_CorreccionSubgenero'] = taxon.x_subgenero.try(:downcase) == hash['subgenero'].try(:downcase) ? nil : taxon.x_subgenero
      end

      if hash.key?('especie')
        correcciones_hash['SCAT_CorreccionEspecie'] = taxon.x_especie.try(:downcase) == hash['especie'].try(:downcase) ? nil : taxon.x_especie
      end

      if hash.key?('autoridad')
        correcciones_hash['SCAT_CorreccionAutorEspecie'] = taxon.x_nombre_autoridad_especie.try(:downcase) == hash['autoridad'].try(:downcase) ? nil : taxon.x_nombre_autoridad_especie
      end

      if hash.key?('infraespecie')
        cat = I18n.transliterate(taxon.x_categoria_taxonomica).gsub(' ','_').downcase

        if CategoriaTaxonomica::CATEGORIAS_INFRAESPECIES.include?(cat)
          correcciones_hash['SCAT_CorreccionInfraespecie'] = taxon.nombre.downcase == hash['infraespecie'].try(:downcase) ? nil : taxon.nombre
        else
          correcciones_hash['SCAT_CorreccionInfraespecie'] = nil
        end
      end

      if hash.key?('autoridad_infraespecie')
        correcciones_hash['SCAT_CorreccionAutorInfraespecie'] = taxon.x_nombre_autoridad_infraespecie.try(:downcase) == hash['autoridad_infraespecie'].try(:downcase) ? nil : taxon.x_nombre_autoridad_infraespecie
      end

      # correcciones_hash['SCAT_CorreccionSinonimo'] = ''  # Sin implementar

    else  # Asociacion vacia
      correcciones_hash['SCAT_CorreccionReino'] = nil if hash.key?('reino')
      correcciones_hash['SCAT_CorreccionDivision'] = nil if hash.key?('division')
      correcciones_hash['SCAT_CorreccionSubdivision'] = nil if hash.key?('subdivision')
      correcciones_hash['SCAT_CorreccionPhylum'] = nil if hash.key?('phylum')
      correcciones_hash['SCAT_CorreccionClase'] = nil if hash.key?('clase')
      correcciones_hash['SCAT_CorreccionSubclase'] = nil if hash.key?('subclase')
      correcciones_hash['SCAT_CorreccionOrden'] = nil if hash.key?('orden')
      correcciones_hash['SCAT_CorreccionSuborden'] = nil if hash.key?('suborden')
      correcciones_hash['SCAT_CorreccionInfraorden'] = nil if hash.key?('infraorden')
      correcciones_hash['SCAT_CorreccionSuperfamilia'] = nil if hash.key?('superfamilia')
      correcciones_hash['SCAT_CorreccionFamilia'] = nil if hash.key?('familia')
      correcciones_hash['SCAT_CorreccionGenero'] = nil if hash.key?('genero')
      correcciones_hash['SCAT_CorreccionSubgenero'] = nil if hash.key?('subgenero')
      correcciones_hash['SCAT_CorreccionEspecie'] = nil if hash.key?('especie')
      correcciones_hash['SCAT_CorreccionAutorEspecie'] = nil if hash.key?('autoridad_especie')
      correcciones_hash['SCAT_CorreccionInfraespecie'] = nil if hash.key?('infraespecie')
      correcciones_hash['SCAT_CorreccionAutorInfraespecie'] = nil if hash.key?('autoridad_infraespecie')
    end

    correcciones_hash
  end

  def validacion_interna(info = {})
    validacion_interna_hash = {}

    if info[:estatus]
      taxon = info[:taxon_valido].present? ? info[:taxon_valido] : info[:taxon]

      validacion_interna_hash['SCAT_Reino_valido'] = taxon.x_reino

      if taxon.x_phylum.present?
        validacion_interna_hash['SCAT_Phylum/Division_valido'] = taxon.x_phylum
      else
        validacion_interna_hash['SCAT_Phylum/Division_valido'] = taxon.x_division
      end

      validacion_interna_hash['SCAT_Clase_valido'] = taxon.x_clase
      validacion_interna_hash['SCAT_Subclase_valido'] = taxon.x_subclase
      validacion_interna_hash['SCAT_Orden_valido'] = taxon.x_orden
      validacion_interna_hash['SCAT_Suborden_valido'] = taxon.x_suborden
      validacion_interna_hash['SCAT_Infraorden_valido'] = taxon.x_infraorden
      validacion_interna_hash['SCAT_Superfamilia_valido'] = taxon.x_superfamilia
      validacion_interna_hash['SCAT_Familia_valido'] = taxon.x_familia
      validacion_interna_hash['SCAT_Genero_valido'] = taxon.x_genero
      validacion_interna_hash['SCAT_Subgenero_valido'] = taxon.x_subgenero
      validacion_interna_hash['SCAT_Especie_valido'] = taxon.x_especie
      validacion_interna_hash['SCAT_Especie_valido'] = taxon.x_especie
      validacion_interna_hash['SCAT_AutorEspecie_valido'] = taxon.x_nombre_autoridad_especie

      # Para la infraespecie
      cat = I18n.transliterate(taxon.x_categoria_taxonomica).gsub(' ','_').downcase
      if CategoriaTaxonomica::CATEGORIAS_INFRAESPECIES.include?(cat)
        validacion_interna_hash['SCAT_Infraespecie_valido'] = taxon.nombre
      else
        validacion_interna_hash['SCAT_Infraespecie_valido'] = nil
      end

      validacion_interna_hash['SCAT_Categoria_valido'] = taxon.x_categoria_taxonomica
      validacion_interna_hash['SCAT_AutorInfraespecie_valido'] = taxon.x_nombre_autoridad_infraespecie
      validacion_interna_hash['SCAT_NombreCient_valido'] = taxon.nombre_cientifico

      # Para la NOM
      nom = taxon.estados_conservacion.where('nivel1=4 AND nivel2=1 AND nivel3>0').distinct
      if nom.length == 1
        taxon.x_nom = nom[0].descripcion
        validacion_interna_hash['SCAT_NOM-059'] = taxon.x_nom
      else
        validacion_interna_hash['SCAT_NOM-059'] = nil
      end

      # Para IUCN
      iucn = taxon.estados_conservacion.where('nivel1=4 AND nivel2=2 AND nivel3>0').distinct
      if iucn.length == 1
        taxon.x_iucn = iucn[0].descripcion
        validacion_interna_hash['SCAT_IUCN'] = taxon.x_iucn
      else
        validacion_interna_hash['SCAT_IUCN'] = nil
      end

      cites = taxon.estados_conservacion.where('nivel1=4 AND nivel2=3 AND nivel3>0').distinct
      if cites.length == 1
        taxon.x_cites = cites[0].descripcion
        validacion_interna_hash['SCAT_CITES'] = taxon.x_cites
      else
        validacion_interna_hash['SCAT_CITES'] = nil
      end

      # Para el tipo de distribucion
      tipos_distribuciones = taxon.tipos_distribuciones.map(&:descripcion).uniq

      if tipos_distribuciones.any?
        taxon.x_tipo_distribucion = tipos_distribuciones.join(',')
        validacion_interna_hash['SCAT_Distribucion'] = taxon.x_tipo_distribucion
      else
        validacion_interna_hash['SCAT_Distribucion'] = nil
      end

      validacion_interna_hash['SCAT_CatalogoDiccionario'] = taxon.sis_clas_cat_dicc
      validacion_interna_hash['SCAT_Fuente'] = taxon.fuente
      validacion_interna_hash['ENCICLOVIDA'] = "http://www.enciclovida.mx/especies/#{taxon.id}"

    else  # Asociacion vacia, solo el error
      validacion_interna_hash['SCAT_Reino_valido'] = nil
      validacion_interna_hash['SCAT_Phylum/Division_valido'] = nil
      validacion_interna_hash['SCAT_Clase_valido'] = nil
      validacion_interna_hash['SCAT_Subclase_valido'] = nil
      validacion_interna_hash['SCAT_Orden_valido'] = nil
      validacion_interna_hash['SCAT_Suborden_valido'] = nil
      validacion_interna_hash['SCAT_Infraorden_valido'] = nil
      validacion_interna_hash['SCAT_Superfamilia_valido'] = nil
      validacion_interna_hash['SCAT_Familia_valido'] = nil
      validacion_interna_hash['SCAT_Genero_valido'] = nil
      validacion_interna_hash['SCAT_Subgenero_valido'] = nil
      validacion_interna_hash['SCAT_Especie_valido'] = nil
      validacion_interna_hash['SCAT_Especie_valido'] = nil
      validacion_interna_hash['SCAT_AutorEspecie_valido'] = nil
      validacion_interna_hash['SCAT_Infraespecie_valido'] = nil
      validacion_interna_hash['SCAT_Infraespecie_valido'] = nil
      validacion_interna_hash['SCAT_Categoria_valido'] = nil
      validacion_interna_hash['SCAT_AutorInfraespecie_valido'] = nil
      validacion_interna_hash['SCAT_NombreCient_valido'] = nil
      validacion_interna_hash['SCAT_NOM-059'] = nil
      validacion_interna_hash['SCAT_IUCN'] = nil
      validacion_interna_hash['SCAT_CITES'] = nil
      validacion_interna_hash['SCAT_Distribucion'] = nil
      validacion_interna_hash['SCAT_CatalogoDiccionario'] = nil
      validacion_interna_hash['SCAT_Fuente'] = nil
      validacion_interna_hash['ENCICLOVIDA'] = nil
    end

    validacion_interna_hash
  end
end
