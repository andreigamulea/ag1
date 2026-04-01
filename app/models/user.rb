class User < ApplicationRecord
  has_many :orders
  has_many :addresses, dependent: :destroy
  has_many :shipping_addresses, -> { shipping.default_first }, class_name: "Address"
  has_many :billing_addresses,  -> { billing.default_first },  class_name: "Address"

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  def admin?
    role == 1
  end

  # Verifică dacă utilizatorul este activ înainte de autentificare
  def active_for_authentication?
    super && active?
  end

  # Mesaj personalizat când contul este inactiv
  def inactive_message
    active? ? super : :account_inactive
  end

  # Metodă pentru dezactivare cont
  def deactivate!
    update(active: false)
  end

  # Metodă pentru reactivare cont (pentru admin)
  def reactivate!
    update(active: true)
  end
end