import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["badge", "hiddenInputsWrapper"]

  toggle(event) {
    const badge = event.currentTarget;
    const id = badge.dataset.id;
    const hiddenInputsWrapper = this.hiddenInputsWrapperTarget;
    const existingInputs = hiddenInputsWrapper.querySelectorAll(`input[value='${id}']`);

    if (existingInputs.length > 0) {
      existingInputs.forEach(input => input.remove());
      badge.classList.remove("bg-primary");
      badge.classList.add("bg-secondary");
    } else {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = "product[category_ids][]";
      input.value = id;
      hiddenInputsWrapper.appendChild(input);
      badge.classList.remove("bg-secondary");
      badge.classList.add("bg-primary");
    }
  }
}