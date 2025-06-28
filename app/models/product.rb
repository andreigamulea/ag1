class Product < ApplicationRecord
  has_one_attached :main_image
  has_many_attached :secondary_images

  enum stock_status: { in_stock: "in_stock", out_of_stock: "out_of_stock" }

  validates :name, :slug, :price, :sku, presence: true
end

# == Schema Information
#
# Product model fields:
#
# name                :string      - Numele produsului (ex: "Hanorac Negru")
# slug                :string      - URL prietenos pentru produs (ex: "hanorac-negru")
# description_title   :string      - Titlu afișat înaintea descrierii produsului
# description         :text        - Descriere detaliată a produsului
#
# price               :decimal     - Prețul de vânzare al produsului (cu TVA)
# cost_price          :decimal     - Costul intern de achiziție (pentru marjă/profit)
# discount_price      :decimal     - Preț promoțional dacă este activă o reducere
#
# sku                 :string      - Cod intern (SKU - Stock Keeping Unit)
# stock               :integer     - Număr de produse disponibile în stoc
# track_inventory     :boolean     - Dacă scade automat stocul la vânzare
# stock_status        :string      - Vizibilitate stoc: "in_stock" / "out_of_stock"
# sold_individually   :boolean     - Permite cumpărarea a doar 1 bucată per comandă
#
# available_on        :date        - Data de la care produsul apare pe site
# discontinue_on      :date        - Data după care produsul nu mai e disponibil
#
# height              :decimal     - Înălțime (cm) pentru livrare
# width               :decimal     - Lățime (cm)
# depth               :decimal     - Adâncime (cm)
# weight              :decimal     - Greutate (kg)
#
# meta_title          :string      - Titlu SEO pentru pagina produsului
# meta_description    :string      - Descriere SEO pentru meta tag
# meta_keywords       :string      - Cuvinte cheie SEO (opțional)
#
# status              :string      - Stare generală: "active" / "inactive"
# featured            :boolean     - Dacă produsul este promovat (ex: homepage)
# requires_login      :boolean     - Dacă utilizatorul trebuie să fie logat pentru a cumpăra
# custom_attributes          :jsonb       - Atribute personalizate (culoare, mărime, etc.)
#
# main_image          :ActiveStorage - Imagine principală
# secondary_images    :ActiveStorage - Imagini secundare multiple
#
# created_at          :datetime    - Data creării
# updated_at          :datetime    - Data ultimei modificări

# de adaugat:
# camp bool - produsul poate fi cumparat doar daca userul e logat




