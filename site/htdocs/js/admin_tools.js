function _open_window(ele, title) {
  var closer = $("windowclose");
  if (!closer) {
    closer = new Element("div", { id: "windowclose" });
    var closer_a = new Element("a", { href: "#" });
    closer_a.update("X");
    closer.appendChild(closer_a);
  }
  else {
    closer.parentNode.removeChild(closer);
  }
  closer.onclick = _close_window.bind(this, ele);
  if (title) {
    ele.firstDescendant().innerHTML = "";
    ele.firstDescendant().appendChild(document.createTextNode(title));
  }
  ele.firstDescendant().appendChild(closer);
  ele.style.display="block";
}

function _close_window(ele) {
  ele.style.display="none";
  return false;
}

var BSE = {};
BSE.InPlaceEdit = Class.create
  (
  {
    initialize: function(ele, options) {
      ele = $(ele);
      ele.observe("click", this.start_edit.bind(this));
      ele.observe("mouseover", this._onmouseover.bind(this));
      ele.observe("mouseout", this._onmouseout.bind(this));
      this.options = Object.clone(this.DefaultOptions);
      Object.extend(this.options, options || { } );
      this.element = ele;
    },
    on_success: function() {
      if (this.saving) {
	this.remove_saving();
	this.remove_form();
	this.saving = false;
      }
    },
    on_error: function(msg) {
      if (this.saving) {
	if (msg) alert(msg);
	this.remove_saving();
	this.form.show();
	this.editing = true;
	this.saving = false;
      }
    },
    start_edit: function() {
      this.element.hide();
      this.make_form();
      this.edit.focus();
    },
    make_form: function() {
      this.form = new Element("form", { className: "bse_ipe" });
      this.form.onsubmit = this._onsubmit.bind(this);
      this.make_edit_field();
      this.make_submit();
      this.make_cancel();
      this.element.hide();
      this.element.parentNode.insertBefore(this.form, this.element);
      this.editing = true;
    },
    make_edit_field: function() {
      if (this.options.rows == 1) {
	this.edit = new Element("input", { className: this.options.edit_class, value: this.options.value });
      }
      else {
	this.edit = new Element("textarea", { className: this.options.edit_class, rows: this.options.rows });
	this.edit.appendChild(document.createTextNode(this.options.value));
      }
      this.form.appendChild(this.edit);
    },
    make_submit: function() {
      this.submit = new Element("input", { type: "submit", className: this.options.submit_class, value: this.options.submit_text });
      this.submit.onclick = this._onsubmit.bind(this);
      this.form.appendChild(this.submit);
    },
    make_cancel: function() {
      this.cancel = new Element("input", { type: "submit", className: this.options.cancel_class, value: this.options.cancel_text });
      this.cancel.onclick = this._oncancel.bind(this);
      this.form.appendChild(this.cancel);
    },
    _onsubmit: function() {
      if (this.editing) {
	this.form.hide();
	this.show_saving();
	this.options.onSave(this, this.edit.value);
	this.editing = false;
	this.saving = true;
      }
      return false;
    },
    show_saving: function() {
      this.saving_ele = new Element("span", { className: this.options.saving_class });
      this.saving_ele.appendChild(document.createTextNode(this.options.saving_text));
      this.element.parentNode.insertBefore(this.saving_ele, this.element);
    },
    remove_saving: function() {
      // it's possible the parent has been destroyed during the save processing
      if (this.element.parentNode)
	this.element.parentNode.removeChild(this.saving_ele);
      delete this.saving_ele;
    },
    remove_form: function() {
      if (this.element.parentNode)
	this.element.parentNode.removeChild(this.form);
      delete this.form;
      delete this.edit;
      delete this.submit;
      delete this.cancel;
    },
    _oncancel: function() {
      if (this.editing) {
	if (this.form.parentNode)
	  this.form.parentNode.removeChild(this.form);
	this.element.show();
	this.editing = false;
      }
      return false;
    },
    _onmouseover: function() {
      this.element.addClassName(this.options.mouseover_class);
    },
    _onmouseout: function() {
      this.element.removeClassName(this.options.mouseover_class);
    },
    DefaultOptions:
    {
      rows: 1,
      form_id: null,
      value: "",
      saving_text: "Saving...",
      saving_class: "bse_ipe_saving",
      edit_class: "bse_ipe_edit",
      submit_class: "bse_ipe_submit",
      submit_text: "Save",
      cancel_class: "bse_ipe_cancel",
      cancel_text: "Cancel",
      mouseover_class: "bse_ipe_over"
    }
  });