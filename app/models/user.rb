class User < ApplicationRecord
  has_many :orders
  has_many :addresses, dependent: :destroy
  has_many :shipping_addresses, -> { shipping.default_first }, class_name: "Address"
  has_many :billing_addresses,  -> { billing.default_first },  class_name: "Address"

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable,
         :omniauthable, omniauth_providers: [:google_oauth2]

  def self.from_omniauth(auth)
    # Verifică dacă există un utilizator cu aceeași adresă de email
    existing_user = find_by(email: auth.info.email)

    if existing_user
      existing_user.assign_attributes(provider: auth.provider, uid: auth.uid, google_token: auth.credentials.token)
      existing_user.save!
      return existing_user
    else
      user = find_or_create_by(provider: auth.provider, uid: auth.uid) do |user|
        user.email = auth.info.email
        user.password = Devise.friendly_token[0, 20]
        user.confirmed_at = Time.current # Google a verificat deja emailul
      end

      user.google_token = auth.credentials.token
      user.save!
      return user
    end
  end

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