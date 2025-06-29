// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import Rails from "@rails/ujs"


import "jquery"
console.log("jquery?", typeof $); // trebuie să zică "function"
import "select2"

document.addEventListener("turbo:load", () => {
  $(".select2").select2();
});


Rails.start()


