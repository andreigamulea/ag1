// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
import AutocompleteController from "./autocomplete_controller"
application.register("autocomplete", AutocompleteController)
import ToggleShippingController from "./toggle_shipping_controller"
application.register("toggle-shipping", ToggleShippingController)
import CategorySelectController from "./category_select_controller"
application.register("category-select", CategorySelectController)

import TestController from "./test_controller"
application.register("test", TestController)
import ProductFormController from "./product_form_controller"
application.register("product-form", ProductFormController)
import ProductVariantsController from "./product_variants_controller"
application.register("product-variants", ProductVariantsController)
import ProductAutogenController from "./product_autogen_controller"
application.register("product-autogen", ProductAutogenController)
