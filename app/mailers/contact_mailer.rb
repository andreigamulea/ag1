# app/mailers/contact_mailer.rb
class ContactMailer < ApplicationMailer
  def contact_email(name, email, message)
    @name = name
    @message = message
    @email = email

    mail(to: 'ayushcellromania@gmail.com', from: 'contact@ayus.ro', subject: 'Mesaj Contact Ayus.ro')
  end
end