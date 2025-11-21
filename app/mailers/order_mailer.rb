# app/mailers/order_mailer.rb
class OrderMailer < ApplicationMailer
  default from: '"Ayus.ro" <comenzi@ayus.ro>'

  def payment_success(order)
    @order = order

    mail(
      to: @order.email,
      reply_to: 'comenzi@ayus.ro',
      bcc: ["ayushcellromania@gmail.com", "comenzi@ayus.ro"],
      subject: "Comanda ta ##{order.id} a fost plătită cu succes!"
    )
  end

  def admin_new_order(order)
    @order = order

    mail(
      to: ["ayushcellromania@gmail.com", "comenzi@ayus.ro"],
      from: 'comenzi@ayus.ro',
      subject: "PLATĂ NOUĂ – Comanda ##{order.id} – #{order.total} RON"
    )
  end
end