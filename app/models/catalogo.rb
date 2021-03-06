class Catalogo < ActiveRecord::Base

  self.table_name = 'catalogos'
  self.primary_key = 'id'

  has_many :especies_catalogos, :class_name => 'EspecieCatalogo'
  #has_one :especie, :through => :especies_catalogos, :class_name => 'EspecieCatalogo', :foreign_key => 'catalogo_id'

  IUCN_QUITAR_EN_FICHA = ['Riesgo bajo (LR): Dependiente de conservación (cd)', 'No evaluado (NE)', 'Datos insuficientes (DD)',
  'Riesgo bajo (LR): Preocupación menor (lc)', 'Riesgo bajo (LR): Casi amenazado (nt)']
  AMBIENTE_EQUIV_MARINO = ['Nerítico', 'Nerítico y oceánico', 'Oceánico']
  NIVELES_PRIORITARIAS = %w(alto medio bajo)

  # Saco el nombre de la categoria de riesgo o comercio ya que al unir los catalogos, los nombres aveces no coinciden
  def nom_cites_iucn(cat_actual = false)
    if nivel1 == 4 && nivel2 > 0 && nivel3 > 0   #se asegura que el valor pertenece a la nom, iucn o cites
      return descripcion if cat_actual

      limites = Bases.limites(id)
      id_inferior = limites[:limite_inferior]
      id_superior = limites[:limite_superior]

      edo_conservacion = Catalogo.where(:nivel1 => nivel1, :nivel2 => nivel2, :nivel3 => 0).where(:id => id_inferior..id_superior).first   #el nombre del edo. de conservacion
      edo_conservacion ? edo_conservacion.descripcion : nil

    else
      nil
    end
  end

  # Saco el nombre del ambiente ya que al unir los catalogos, los nombres aveces no coinciden
  def ambiente
    if nivel1 == 2 && nivel2 == 6 && nivel3 > 0   #se asegura que el valor pertenece al ambiente
      descripcion
    else
      nil
    end
  end

  # Saco el nivel de la especie prioritaria
  def prioritaria
    if nivel1 == 4 && nivel2 == 4 && nivel3 > 0   #se asegura que el valor pertenece a prioritaria del diario oficial (DOF)
      descripcion
    elsif nivel1 == 4 && nivel2 == 5 && nivel3 > 0   #se asegura que el valor pertenece a prioritaria de de la CONABIO
      nil
    end
  end

  def self.ambiente_todos
    ambiente = Catalogo.where(:nivel1 => 2, :nivel2 => 6).where('nivel3 > 0').map(&:descripcion).uniq
    ambiente.delete_if{|a| AMBIENTE_EQUIV_MARINO.include?(a)}
  end

  def self.nom_cites_iucn_todos
    nom = where(:nivel1 => 4, :nivel2=> 1).where('nivel3 > 0').map(&:descripcion).uniq
    nom = [nom[3],nom[1],nom[0],nom[2]]#Orden propuesto por cgalindo
    # Esta categoria de IUCN esta repetida y no tenia nada asociado
    iucn = where(:nivel1 => 4, :nivel2=> 2).where("nivel3 > 0 AND descripcion != 'Riesgo bajo (LR): Casi amenazada (nt)'").map(&:descripcion).uniq
    iucn = [iucn[7],iucn[6],iucn[9],iucn[8],iucn[4],iucn[3],iucn[2],iucn[1],iucn[0],iucn[5]]#IDEM, el iucn[5] se quita en el helper, consultar con dhernandez ASAP
    cites = where(:nivel1 => 4, :nivel2=> 3).where('nivel3 > 0').map(&:descripcion).uniq #Esta ya viene en orden (I,II,III)
    {:nom => nom, :iucn => iucn, :cites => cites}
  end
end
