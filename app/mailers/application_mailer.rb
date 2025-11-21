# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  default from: "contact@ayus.ro"
  layout "mailer"
end