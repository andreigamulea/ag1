class Product < ApplicationRecord
  has_one_attached :main_image
  has_many_attached :secondary_images
  has_many_attached :attached_files
  has_and_belongs_to_many :categories


  



serialize :external_image_urls, Array
#serialize :external_image_urls, coder: JSON




  


  enum stock_status: { in_stock: "in_stock", out_of_stock: "out_of_stock" }

  validates :name, :slug, :price, :sku, presence: true
  enum product_type: {
      physical: "physical",
      digital: "digital"
    }
  enum delivery_method: {
  shipping: "shipping",
  produs_digital: "produs digital",
  download: "download",
  external_link: "external_link"
}  

end

# == Schema Information
#
# Product model fields:
#
# name                      :string      - Numele produsului (ex: "Hanorac Negru")
# slug                      :string      - URL prietenos pentru produs (ex: "hanorac-negru")
# description_title         :string      - Titlu afișat înaintea descrierii produsului
# description               :text        - Descriere detaliată a produsului
#
# price                     :decimal     - Prețul de vânzare al produsului (cu TVA)
# cost_price                :decimal     - Costul intern de achiziție (pentru marjă/profit)
# discount_price            :decimal     - Preț promoțional dacă este activă o reducere
#
# sku                       :string      - Cod intern (SKU - Stock Keeping Unit)
# stock                     :integer     - Număr de produse disponibile în stoc
# track_inventory           :boolean     - Dacă scade automat stocul la vânzare
# stock_status              :string      - Vizibilitate stoc: "in_stock" / "out_of_stock"
# sold_individually         :boolean     - Permite cumpărarea a doar 1 bucată per comandă
#
# available_on              :date        - Data de la care produsul apare pe site
# discontinue_on            :date        - Data după care produsul nu mai e disponibil
#
# height                    :decimal     - Înălțime (cm) pentru livrare
# width                     :decimal     - Lățime (cm)
# depth                     :decimal     - Adâncime (cm)
# weight                    :decimal     - Greutate (kg)
#
# meta_title                :string      - Titlu SEO pentru pagina produsului
# meta_description          :string      - Descriere SEO pentru meta tag
# meta_keywords             :string      - Cuvinte cheie SEO (opțional)
#
# status                    :string      - Stare generală: "active" / "inactive"
# featured                  :boolean     - Dacă produsul este promovat (ex: homepage)
# requires_login            :boolean     - Dacă utilizatorul trebuie să fie logat pentru a cumpăra
# product_type              :string      - Tipul produsului: "physical" / "digital"
# custom_attributes         :jsonb       - Atribute personalizate (culoare, mărime, etc.)
#
# delivery_method           :string      - Modul de livrare: "shipping", "download", "external_link"
# visible_to_guests         :boolean     - Dacă produsul este vizibil fără să fii logat
# taxable                   :boolean     - Dacă se aplică TVA la acest produs
# coupon_applicable         :boolean     - Dacă se poate aplica cupon de reducere

#
# main_image                :ActiveStorage - Imagine principală
# secondary_images          :ActiveStorage - Imagini secundare multiple
# download_file             :ActiveStorage - Fișier atașat pentru produse digitale
#
# created_at                :datetime    - Data creării
# updated_at                :datetime    - Data ultimei modificări
