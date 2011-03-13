var BSEDialog = Class.create({
  initialize: function(options) {
    this.options = Object.extend
    (
      {
	modal: false,
	title: "Missing title",
	validator: new BSEValidator,
	top_class: "bse_dialog",
	modal_class: "bse_modal",
	title_class: "bse_title",
	error_class: "bse_error",
	submit_wrapper_class: "bse_submit_wrapper",
	submit: "Submit",
	cancel: false,
	cancel_text: "Cancel",
	onCancel: function(dlg) { dlg.close(); },
	dynamic_validation: true,
	dynamic_interval: 1000
      },
      options);
    this._build();
    if (this.options.dynamic_validation)
      this._start_validation();
    this._show();
  },
  _reset_errors: function() {
    this._fields.clear_error();
  },
  error: function(msg) {
    this._reset_errors();
    this._error.update(msg);
    this._error.style.display = "block";
  },
  field_errors: function(errors) {
    this._reset_errors();
    if (errors.constructor == Hash) {
      errors.each(function(entry) {
	this._fields.set_error(entry.key, entry.value);
      }.bind(this));
    }
    else {
      for (var i in errors) {
	this._fields.set_error(i, errors[i]);
      }
    }
  },
  field: function(name) {
    return this._values.get(name);
  },
  bse_error: function(error) {
    if (error.error_code == "FIELD") {
	     this.field_errors(error.errors);
    }
    else if (error.msg) {
      this.error(error.msg);
    }
    else {
      this.error(error_code);
    }
  },
  close: function() {
    this.top.remove();
    if (this._interval)
      window.clearInterval(this._interval);
  },
  _build: function() {
    var top;
    this.div = new Element("div", { className: this.options.top_class });
    if (this.options.modal) {
      this.wrapper = new Element("div", { className: this.options.modal_class });
      top = this.wrapper;
      this.wrapper.appendChild(this.div);
    }
    else {
      top = this.div;
    }
    this.top = top;
    this.title = new Element("div", { className: this.options.title_class });
    this.title.update(this.options.title);
    this.div.appendChild(this.title);
    this._error = new Element("div", { className: this.options.error_class });
    this._error.style.display = "none";
    this.div.appendChild(this.title);
    this.div.appendChild(this._error);
    this.form = new Element("form", { action: "#" });
    this.form.observe("submit", this._on_submit.bind(this));
    this.div.appendChild(this.form);
    this.field_error_divs = {};
    this.field_wrapper_divs = {};
    this.fields = {};
    this._add_fields(this.form, this.options.fields);
    var sub_wrapper = new Element("div", { className: this.options.submit_wrapper_class });
    if (this.options.cancel) {
      this.cancel = new Element("input", { type: "submit", value: this.options.cancel_text, className: "cancel" });
      this.cancel.observe("click", this._on_cancel.bindAsEventListener(this));
      sub_wrapper.appendChild(this.cancel);
    }
    this.submit = new Element("input", { type: "submit", value: this.options.submit });
    sub_wrapper.appendChild(this.submit);
    this.form.appendChild(sub_wrapper);
  },
  _show: function() {
    var body = $$("body")[0];
    body.appendChild(this.top);
    var top_px = (document.viewport.getHeight() - this.div.getHeight()) / 2;
    if (top_px < 20) {
      this.div.style.overflowX = "scroll";
      this.div.style.top = "10px";
      this.div.style.height = (this.viewport.getHeight()-20) + "px";
    }
    else {
      this.div.style.top = top_px + "px";
    }
    this.div.style.left = (document.viewport.getWidth() - this.div.getWidth()) / 2 + "px";
    if (this.wrapper) {
      this.wrapper.style.height = "100%";
    }
  },
  _add_fields: function(parent, fields) {
    this._fields = new BSEDialog.Fields(this.options);
    this._value_fields = this._fields.value_fields();
    this._values = new Hash();
    this._value_fields.each(function(field) {
      this._values.set(field.name(), field);
    }.bind(this));
    this._elements = this._fields.elements();
    this._elements.each(function(ele) {
      this.form.appendChild(ele);
    }.bind(this));
  },
  _start_validation: function() {
    if (this.options.validator) {
      this._update_submit();
      this._interval = window.setInterval(this._update_submit.bind(this), this.options.dynamic_interval);
    }
  },
  _update_submit: function() {
    var errors = new Hash();
    this.submit.disabled = !this.options.validator.validate(this._values, errors);
  },
  _on_submit: function(event) {
    event.stop();
    if (this.options.validator) {
      var errors = new Hash();
      if (!this.options.validator.validate(this._values, errors)) {
	this.field_errors(errors);
	return;
      }
    }
    this.options.onSubmit(this);
  },
  _on_cancel: function(event) {
    event.stop();
    this.options.onCancel(this);
  }
});

// wraps one or more fields
//
BSEDialog.Fields = Class.create({
  initialize: function(options) {
    this.options = Object.extend({}, options);

    this._fields = {};
    this._value_fields = [];
    this._elements = [];
    options.fields.each(function(field) {
      var cls = BSEDialog.FieldTypes[field.type || "text"];
      var fieldobj = new cls(field);
      fieldobj.value_fields().each(function(field) {
	this._fields[fieldobj.name()] = fieldobj;
      }.bind(this, fieldobj));
      this._value_fields = this._value_fields.concat(fieldobj.value_fields());
      this._elements = this._elements.concat(fieldobj.elements());
    }.bind(this));
  },
  set_error: function(name, message) {
    this._fields[name].set_error(name, message);
  },
  clear_error: function() {
    for (var i in this._fields) {
      this._fields[i].clear_error();
    }
  },
  value_fields: function() {
    return this._value_fields;
  },
  elements: function() {
    return this._elements;
  }
});

BSEDialog.FieldTypes = {};

// field objects provide the following methods:
//
// clear_error() - clear all error indicators
// set_error(name, message) - set the error indicator for the named field
// input() - return the underlying input tag (intended for use with file
//      fields, many field types will not have a single input)
// value_fields() return the fields that actually have a value.  For a field
//   this is the child fields of the fieldset.  For value fields just return
//   [ this ]
// elements() returns the top-level elements for each field, for an input
//   this is the wrapper div, for a field set, the fieldset itself
//
// Fields returned by value_fields() must also provide:
// value() - return the value of the given field
// description() - text description of the field
// name() - name of the value
// rules() - validation rules either as a ; separated string or an array
// has_value() - returns true if the field has a non-empty value
// required() - returns true if the field is marked required
//
BSEDialog.FieldTypes.Base = Class.create({
  _make_wrapper: function() {
    var wrapper = new Element("div", { className: this.options.field_wrapper_class });
    if (this.options.required)
      wrapper.addClassName(this.options.field_required_class);

    return wrapper;
  },
  _make_label: function() {
    return new Element("label", { htmlFor: this._input.identify() });
  },
  _make_error: function() {
    var err_div = new Element("div", { className: this.options.field_error_class });
    err_div.style.display = "none";
    return err_div;
  },
  name: function() {
    return this.options.name;
  },
  clear_error: function() {
    this._error.update("");
    this._error.style.display = "none";
    this.elements().each(function(ele) {
      ele.removeClassName(this.options.field_invalid_class);
    }.bind(this));
  },
  set_error: function(name, message) {
    this._error.update(message);
    this._error.style.display = "block";
    this.elements().each(function(ele) {
      ele.addClassName(this.options.field_invalid_class);
    }.bind(this));
  },
  input: function() {
    return null;
  },
  description: function() {
    return null;
  },
  required: function() {
    return this.options.required;
  },
  value_fields: function() {
    return [ this ];
  },
  defaults: function() {
    return BSEDialog.FieldTypes.Base.defaults;
  }
});

BSEDialog.FieldTypes.Base.defaults = {
  field_wrapper_class: "bse_field_wrapper",
  field_error_class: "bse_field_error",
  field_required_class: "bse_required",
  field_invalid_class: "bse_invalid",
  rules: [],
  required: false
};

BSEDialog.FieldTypes.input = Class.create(BSEDialog.FieldTypes.Base, {
  initialize: function(options) {
    this.options = Object.extend(Object.extend({}, this.defaults()), options);
    this._div = this._make_wrapper();
    this._input = this._make_input();
    this._label = this._make_label();
    this._label.update(this.description());
    this._error = this._make_error();
    
    this._div.appendChild(this._label);
    this._div.appendChild(this._input);
    this._div.appendChild(this._error);
  },
  _make_input: function() {
    return new Element(
      "input",
      {
	name: this.options.name,
	type: this.options.type,
	value: this.options.value
      });
  },
  value: function() {
    return this._input.value;
  },
  elements: function() {
    return [ this._div ];
  },
  name: function() {
    return this.options.name;
  },
  description: function() {
    return this.options.label || this.options.name;
  },
  rules: function() {
    return this.options.rules;
  },
  has_value: function() {
    return /\S/.test(this.value());
  },
  defaults: function() {
    return Object.extend(
      Object.extend(
	{}, BSEDialog.FieldTypes.Base.defaults
      ), BSEDialog.FieldTypes.input.defaults);
  }
});

BSEDialog.FieldTypes.input.defaults = {
  type: "text",
  value: ""
};

BSEDialog.FieldTypes.text = BSEDialog.FieldTypes.input;

BSEDialog.FieldTypes.password = BSEDialog.FieldTypes.input;

BSEDialog.FieldTypes.textarea = Class.create(BSEDialog.FieldTypes.input, {
  _make_input: function() {
    return new Element("textarea", {
      name: this.options.name,
      value: this.options.value,
      cols: this.options.cols,
      rows: this.options.rows
    });
  }
});

BSEDialog.FieldTypes.select = Class.create(BSEDialog.FieldTypes.input, {
  _make_input: function() {
    var input = new Element("select", { name: this.options.name });
    var values = this.options.values;
    for (var i = 0; i < values.length; ++i) {
      var val = values[i];
      var def = this.option.value != null && this.option.value == val.key;
      input.options[input.options.length] =
	new Option(val.label, val.value, def);
    }
    return input;
  }
});

BSEDialog.FieldTypes.radio = Class.create(BSEDialog.FieldTypes.Base, {
  initialize: function() {
  },
  value: function() {
  },
  input: function() {
  }
});

BSEDialog.FieldTypes.frameset = Class.create(BSEDialog.FieldTypes.Base, {
  initialize: function(options) {
    this.options = Object.extend(Object.extend({}, BSEDialog.FieldTypes.frameset.defaults), options);
    this._element = new Element("fieldset");
    if (f.label) {
      var legend = new Element("legend")
      legend.update(f.label);
      this._element.appendChild(legend);
    }
    
    this._fields = new BSEDialog.Fields(options);
  },
  value_fields: function() {
    return this._fields.value_fields();
  },
  clear_error: function() {
    this._fields.clear_error();
  },
  set_error: function(name, message) {
    this._fields.set_error(name, message);
  }
});

BSEDialog.FieldTypes.help = Class.create(BSEDialog.FieldTypes.Base, {
  initialize: function(options) {
    this._element = new Element("div");
    this._element.update(f.helptext);
  },
  value_fields: function() {
    // nothing to see here, move along
    return [];
  }
});