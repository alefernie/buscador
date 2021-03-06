# Todo lo concerniente con querys y las bases de biotica
module Bases

  EQUIVALENCIA =
      {
          'bibliografias' => 'Bibliografia',
          'catalogos' => 'CatalogoNombre',
          'categorias_taxonomicas' => 'CategoriaTaxonomica',
          'especies' => 'Nombre',
          'especies_bibliografias' => 'RelNombreBiblio', #*
          'especies_catalogos' => 'RelNombreCatalogo',
          'especies_estatuses' => 'Nombre_Relacion',
          #'especies_estatuses_bibliografias' => 'RelacionBibliografia',
          'especies_regiones' => 'RelNombreRegion',
          'estatuses' => 'Tipo_Relacion',
          'nombres_comunes' => 'Nomcomun',
          'nombres_regiones' => 'RelNomNomComunRegion',
          'nombres_regiones_bibliografias' => 'RelNomNomcomunRegionBiblio',
          'regiones' => 'Region',
          'tipos_distribuciones' => 'TipoDistribucion',
          'tipos_regiones' => 'TipoRegion',
      }

  def self.id_en_vista_a_id_original(id)
    id%1000000
  end

  def self.id_original_a_numero_base(id)
    id/1000000 - 1
  end

  # Para buscar en un rango de una base de acuerdo al ID de bios
  def self.limites(id)
    limite_inferior = (id/1000000)*1000000 + 1
    limite_superior = (id/1000000)*1000000 + 999999
    {:limite_inferior => limite_inferior, :limite_superior => limite_superior}
  end

  def self.conecta_a(base)
    ActiveRecord::Base.establish_connection base
  end

  def self.ejecuta(query)
    ActiveRecord::Base.connection.execute query
  end

  def self.id_original_a_id_en_vista(id, base=nil)
    base = ActiveRecord::Base.connection_config[:database] unless base.present?
    base_num = CONFIG.bases.index(base) + 1   #numero de base
    id.to_i + base_num*1000000     # ID en la vista
  end

  def self.insert_en_volcado(id, base, tabla)
    condiciones = condiciones(tabla, id, base)
    query = "INSERT master.dbo.#{tabla} SELECT * FROM master.dbo.#{tabla}_0 WHERE #{condiciones}"
    ejecuta(query)
  end

  def self.delete_en_volcado(id, base, tabla)
    condiciones = condiciones(tabla, id, base)
    query = "DELETE master.dbo.#{tabla} WHERE #{condiciones}"
    ejecuta(query)
  end

  def self.update_en_volcado(id, base, tabla)
    condiciones = condiciones(tabla, id, base, true)
    modelo = I18n.t("nombres_modelos.#{tabla}")
    # Los pone en forma de SET attr = e_0.attr
    attributos = modelo.constantize.attribute_names.map{|att| "#{att}=t_0.#{att}"}.join(',')
    query = "UPDATE master.dbo.#{tabla} SET #{attributos} "
    query+= "FROM (master.dbo.#{tabla} AS t INNER JOIN #{tabla}_0 AS t_0 ON t.id=t_0.id) WHERE #{condiciones}"
    ejecuta(query)
  end

  def self.condiciones(tabla, id, base, con_update=false)
    ids = id.split('-')
    primary_key_sql = ''

    # primary key de la tabla del volcado
    modelo = I18n.t("nombres_modelos.#{tabla}")
    primary_key = modelo.constantize.primary_key
    primary_key = primary_key.split if primary_key.is_a? String

    # une las condiciones
    primary_key.each_with_index do |pk, index|
      #aumenta tambien los ceros correespondientes
      if con_update
        # especial para el alias t_0.attr
        primary_key_sql+= "t_0.#{pk}=#{id_original_a_id_en_vista(ids[index], base)} AND "
      else
        primary_key_sql+= "#{pk}=#{id_original_a_id_en_vista(ids[index], base)} AND "
      end
    end
    primary_key_sql[0..-6]
  end

  def self.base_del_ambiente
    ActiveRecord::Base.configurations[Rails.env]['database']
  end

  # Limpia el sql para que no se tarde cuando hace un distinct en SQL Server,
  # lamejor forma de hacer ersto es cambiar el comportamiento de la gema de active record
  def self.distinct_limpio(sql)
    # Quita el select repetido del inicio
    q = sql.gsub("\n",'').sub(/^SELECT.+SELECT/, 'SELECT DISTINCT')
    # Quita el DENSE_RANK y demas
    q = q.sub(/, DENSE_RANK.+_row_num FROM/, ' FROM')
    # Quita la parte final y con ello se nos fue el order by original
    q.sub(/\) AS __sq .+/, '')
  end
end
