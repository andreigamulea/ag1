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