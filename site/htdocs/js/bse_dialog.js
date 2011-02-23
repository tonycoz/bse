var BSEDialog = Class.create({
  initialize: function(options) {
    this.options = Object.extend(
      Object.extend({}, this.defaults()), options);
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
    this._error.show();
    this._error_animate();
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
    this._error_animate();
  },
  _error_animate: function() {
    this.options.error_animate(this, this.div);
  },
  field: function(name) {
    return this._values.get(name);
  },
  bse_error: function(error) {
    if (error.error_code == "FIELD") {
      this.field_errors(error.errors);
    }
    else if (error.message) {
      this.error(error.message);
    }
    else {
      this.error(error_code);
    }
  },
  close: function() {
    this.div.remove();
    if (this.wrapper)
      this.wrapper.remove();
    if (this._interval)
      window.clearInterval(this._interval);
  },
  busy: function() {
    this._spinner.show();
  },
  unbusy: function() {
    this._spinner.hide();
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
    this.form = new Element("form", { action: "#" });
    this.form.observe("submit", this._on_submit.bind(this));
    this.div.appendChild(this.form);

    var parent;
    if (this.options.fieldset_wrapper) {
      var fs = new Element("fieldset");
      this.title = new Element("legend");
      this.title.update(this.options.title);
      fs.appendChild(this.title);
      this.form.appendChild(fs);
      parent = fs;
    }
    else {
      parent = this.form;
      this.title = new Element("div", { className: this.options.title_class });
      this.title.update(this.options.title);
      this.div.appendChild(this.title);
    }
    this._error = new Element("div", { className: this.options.error_class });
    this._error.hide();
    parent.appendChild(this._error);
    this.field_error_divs = {};
    this.field_wrapper_divs = {};
    this.fields = {};
    this._add_fields(parent, this.options.fields);
    var button_p = new Element("p", { className: this.options.submit_wrapper_class });
    var sub_wrapper = new Element("span");
    this._progress = new BSEDialog.ProgressBar();
    button_p.appendChild(this._progress.element());
    
    this._spinner = new Element("span", {className: this.options.spinner_class });
    this._spinner.hide();
    this._spinner.update(this.options.spinner_text);
    sub_wrapper.appendChild(this._spinner);
    if (this.options.cancel) {
      this.cancel = this._make_cancel();
      this.cancel.observe("click", this._on_cancel.bindAsEventListener(this));
      sub_wrapper.appendChild(this.cancel);
    }
    this.submit = this._make_submit();
    sub_wrapper.appendChild(this.submit);
    button_p.appendChild(sub_wrapper);
    this.form.appendChild(button_p);
  },
  _make_cancel: function() {
    var cancel = new Element("button", {
      type: "button",
      className: this.options.cancel_base_class
    });
    if (this.options.cancel_class)
      cancel.addClassName(this.options.cancel_class);
    cancel.update(this.options.cancel_text);

    return cancel;
  },
  _make_submit: function() {
    var submit = new Element("button", {
      type: "submit",
      className: this.options.submit_base_class
    });
    if (this.options.submit_class)
      submit.addClassName(this.options.submit_class);
    submit.update(this.options.submit);

    return submit;
  },
  _show: function() {
    var body = $$("body")[0];
    body.insertBefore(this.div, body.firstChild);
    if (this.wrapper)
      body.insertBefore(this.wrapper, body.firstChild);
    if (this.options.position) {
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
    }
    this._fields.inDocument();
    //if (this.wrapper) {
    //  this.wrapper.style.height = "100%";
    //}
  },
  _add_fields: function(parent, fields) {
    this._fields = new BSEDialog.Fields(this.options);
    this._value_fields = this._fields.value_fields();
    this._values = new Hash();
    this._value_fields.each(function(field) {
      this._values.set(field.name(), field);
    }.bind(this));
    this._elements = this._fields.elements();
    this._elements.each(function(parent, ele) {
      parent.appendChild(ele);
    }.bind(this, parent));
  },
  _start_validation: function() {
    if (this.options.validator) {
      this._update_submit();
      this._interval = window.setInterval(this._update_submit.bind(this), this.options.dynamic_interval);
    }
  },
  _update_submit: function() {
    var errors = new Hash();
    this.submit.disabled = this.options.validator.validate(this._values, errors) ? "" : "disabled";
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
  },
  defaults: function() {
    return BSEDialog.defaults;
  },
  progress_start: function(note) {
    this._progress.start(note);
  },
  progress: function(frac, note) {
    this._progress.progress(frac, note);
  },
  progress_end: function() {
    this._progress.end();
  },
  progress_note: function(note) {
    this._progress.note(note);
  },
  enable: function() {
    this.form.enable();
  },
  disable: function() {
    this.form.disable();
  }
});

BSEDialog.defaults = {
  modal: false,
  title: "Missing title",
  validator: new BSEValidator,
  top_class: "window dialog",
  modal_class: "bse_modal",
  title_class: "bse_title",
  error_class: "bse_error",
  submit_wrapper_class: "buttons",
  submit: "Submit",
  cancel: false,
  cancel_text: "Cancel",
  onCancel: function(dlg) { dlg.close(); },
  dynamic_validation: true,
  dynamic_interval: 1000,
  position: false,
  fieldset_wrapper: true,
  cancel_base_class: "button bigrounded cancel",
  cancel_class: "gray",
  submit_base_class: "button bigrounded",
  submit_class: "green",
  error_animate: function(dlg, div) {
    Effect.Shake(div);
  },
  spinner_class: "spinner",
  spinner_text: "Busy"
};


// wraps one or more fields
//
BSEDialog.Fields = Class.create({
  initialize: function(options) {
    this.options = Object.extend({}, options);

    this._fields = {};
    this._value_fields = [];
    this._elements = [];
    this._fieldobjs = [];
    options.fields.each(function(field) {
      var cls = BSEDialog.FieldTypes[field.type || "text"];
      var fieldobj = new cls(field);
      this._fieldobjs.push(fieldobj);
      fieldobj.value_fields().each(function(field) {
	this._fields[field.name()] = field;
      }.bind(this));
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
  },
  inDocument: function() {
    this._fieldobjs.each(function(f) {
      f.inDocument();
    });
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
    err_div.hide();
    return err_div;
  },
  name: function() {
    return this.options.name;
  },
  clear_error: function() {
    this._error.update("");
    this._error.hide();
    this.elements().each(function(ele) {
      ele.removeClassName(this.options.field_invalid_class);
    }.bind(this));
  },
  set_error: function(name, message) {
    this._error.update(message);
    this._error.show();
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
  },
  set_object: function(object) {
    this._object = object;
  },
  object: function() {
    return this._object;
  },
  // called when the field becomes part of the document
  inDocument: function() {
  },
  default_options: function() {
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
    var span = new Element("span");
    this._input = this._make_input();
    this._label = this._make_label();
    this._label.update(this.description());
    this._error = this._make_error();
    
    span.appendChild(this._input);
    this._div.appendChild(this._label);
    this._div.appendChild(span);
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
    var ta = new Element("textarea", {
      name: this.options.name,
      value: this.options.value,
      cols: this.options.cols,
      rows: this.options.rows
    });
    ta.update(this.options.value);

    return ta;
  },
  defaults: function($super) {
    return Object.extend({}, Object.extend($super(), {
      rows: 4,
      cols: 60
    }));
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

BSEDialog.FieldTypes.fieldset = Class.create(BSEDialog.FieldTypes.Base, {
  initialize: function(options) {
    this.options = Object.extend(Object.extend({}, BSEDialog.FieldTypes.fieldset.defaults), options);
    this._element = new Element("fieldset");
    if (this.options.legend) {
      var legend = new Element("legend")
      legend.update(this.options.legend);
      this._element.appendChild(legend);
    }
    
    this._fields = new BSEDialog.Fields(options);
    this._fields.elements().each(function(ele) {
      this._element.appendChild(ele);
    }.bind(this));
  },
  value_fields: function() {
    return this._fields.value_fields();
  },
  clear_error: function() {
    this._fields.clear_error();
  },
  set_error: function(name, message) {
    this._fields.set_error(name, message);
  },
  elements: function() {
    return [ this._element ];
  },
  inDocument: function() {
    this._fields.inDocument();
  }
});

BSEDialog.FieldTypes.fieldset.defaults = {
};

BSEDialog.FieldTypes.help = Class.create(BSEDialog.FieldTypes.Base, {
  initialize: function(options) {
    this._element = new Element("div");
    this._element.update(options.helptext);
  },
  value_fields: function() {
    // nothing to see here, move along
    return [];
  },
  elements: function() {
    return [ this._element ];
  }
});

BSEDialog.FieldTypes.image = Class.create(BSEDialog.FieldTypes.Base, {
  initialize: function(options) {
    this.options = Object.extend(Object.extend({}, this.default_options()), options);
    // general container
    var wrapper = new Element("fieldset", {
      className: "bse_image_field"
    });
    this._element = wrapper;
    var legend = new Element("legend");
    legend.update(this.options.label);
    wrapper.appendChild(legend);

    var disp = new Element("img", {
      className: "display"
    });
    this._image_display = disp;
    this.options.value = Object.extend({
      src: "",
      alt: "",
      name: "",
      description: "",
      display_name: ""
    }, this.options.value || {});
    if (this.options.value) {
      if (this.options.value.src)
	disp.src = this.options.value.src;
      else if (this.options.value.file) {
	new BSEDialog.ImagePlaceholder({
	  file: this.options.value.file,
	  onLoad: function(disp, ph) {
	    disp.src = ph.src();
	  }.bind(this, disp)
	});
      }
	
      disp.alt = this.options.value.alt;
    }
    
    wrapper.appendChild(disp);
    var file = new Element("input", {
      type: "file"
    });
    this._file_input = file;
    wrapper.appendChild(file);

    if (BSEAPI.can_drag_and_drop()) {
      BSEAPI.make_drop_zone({
	element: disp,
	onDrop: function (files) {
	  this.clear_error();
	  var file = files[0];
	  if (!/\.(jpe?g|png|gif)$/i.test(file.fileName)) {
	    this.set_error("Only image files accepted");
	    return;
	  }
	  this._dropped_file = file;
	  this.value.display_name = file.fileName;
	  if (window.URL && window.URL.createObjectURL) {
	    this._update_thumb_dropped(window.URL.createObjectURL(file));
	  }
	  else if (window.FileReader) {
	    var fr = new FileReader;
	    fr.onload = function(fr) {
	      this._update_thumb_dropped(fr.result);
	    }.bind(this, fr);
	    fr.readAsDataURL(file);
	  }

	  this._file_input.hide();
	  this._dropped_name.update(this.value.display_name);
	  this._dropped_name.show();
	}.bind(this)
      });
      this._dropped_name = new Element("span", {
	className: "dropped_name"
      });
      this._dropped_name.hide();
      wrapper.appendChild(this._dropped_name);
    }

    var fields = new Array();
    if (!this.options.hide_alt) {
      fields.push({
	label: "Alt",
	type: "text",
	name: "alt",
	value: this.options.value.alt
      });
    }
    if (!this.options.hide_name) {
      fields.push({
	label: "Name",
	type: "text",
	name: "name",
	value: this.options.value.name
      });
    }
    if (!this.options.hide_description) {
      fields.push({
	label: "Description",
	type: "text",
	name: "description",
	value: this.options.value.description
      });
    }

    if (fields.length != 0) {
      var more = new Element("div", {
	className: "more"
      });
      more.update("more");
      more.observe("click", function () {
	if (this._extras_shown)
	  this._extras.hide();
	else
	  this._extras.show();
	this._extras_shown = !this._extras_shown;
      }.bind(this));
      wrapper.appendChild(more);
      
      // extra image info
      var extras = new Element("div", {
	className: "extras"
      });
      this._extras = extras;
      this._extras_shown = false;
      this._extra_fields = new BSEDialog.Fields({
	fields: fields
      });
      this._extra_fields.elements().each(function(ele) {
	this._extras.appendChild(ele);
      }.bind(this));
      extras.hide();
      wrapper.appendChild(extras);
    }
    this._error = this._make_error();
    wrapper.appendChild(this._error);
  },
  _update_thumb_dropped: function(url) {
    // a bit hacky
    var img = new Element("img");
    img.onload = function(img) {
      var canvas = new Element("canvas", {
	width: 80,
	height: 80
      });

      var ctx = canvas.getContext("2d");
      var max_dim = img.width > img.height ? img.width : img.height;
      var scale = 80 / max_dim;
      var sc_width = img.width * scale;
      var sc_height = img.height * scale;
      var off_x = (80-sc_width)/2;
      var off_y = (80-sc_height)/2;
      ctx.drawImage(img, off_x, off_y, 80-off_x*2, 80-off_y*2);
      this._image_display.src = canvas.toDataURL();
    }.bind(this, img);
    img.src = url
  },
  default_options: function() {
    return {};
  },
  elements: function() {
    return [ this._element ];
  },
  rules: function() {
    return [];
  },
  has_value: function() {
    if (this._dropped_file)
      return true;
    if (this._file_input.value.length)
      return true;

    return false;
  },
  value: function() {
    if (this._dropped_file)
      return this._dropped_file.fileName;

    return this._file_input.value;
  },
  object: function() {
    var obj = {};
    if (this._dropped_file) {
      obj.file = this._dropped_file;
      obj.display_name = obj.file.fileName;
    }
    else if (this._file_input.value != "") {
      obj.file = this._file_input;
      obj.display_name = obj.file.value;
    }
    if (this._extra_fields) {
      this._extra_fields.value_fields().each(function(obj, field) {
	obj[field.name()] = field.value();
      }.bind(this, obj));
    }

    return obj;
  }
});

BSEDialog.FieldTypes.gallery = Class.create(BSEDialog.FieldTypes.Base, {
  initialize: function(options) {
    this.options = Object.extend(
      Object.extend({}, this.default_options()),
      options);
    this._element = new Element("fieldset", {
      className: "bse_image_gallery"
    });
    this._undo_history = [];
    var legend = new Element("legend");
    legend.update(this.options.label);
    this._element.appendChild(legend);
    this._images_element = new Element("div", {
      className: "bse_gallery_imagelist"
    });
    // original images that have been removed
    this._deleted = [];
    this._element.appendChild(this._images_element);
    this._element.appendChild(this._make_input_div());
    this._images = this.options.value.map(function(im) {
      return {
	type: "old",
	image: im,
	display_name: im.display_name,
	id: im.id,
	changed: false,
	alt: im.alt,
	description: im.description,
	name: im.name,
	src: im.src
      };
    });
    this._autoid = 1;
    this._populate_images();
  },
  _make_input_div: function() {
    var div = new Element("div");
    this._file_input = this._make_file_input();
    var label = new Element("label", {
      "for": this._file_input.identify()
    });
    label.update(this.options.file_input_label);
    var add = new Element("span", {
      className: "widget add"
    });
    add.update("Add");
    add.observe("click", this._add_file_input.bind(this));
    div.appendChild(label);
    div.appendChild(this._file_input);
    div.appendChild(add);

    return div;
  },
  _make_file_input: function() {
    var file = new Element("input", {
      type: "file"
    });

    if (this._file_input)
      file.id = this._file_input.identify();

    if (BSEAPI.can_drag_and_drop())
      file.multiple = true;

    return file;
  },
  _add_file_input: function() {
    var file = this._file_input;
    if (file.value.length > 0) {
      if (BSEAPI.can_drag_and_drop()) {
	for (var i = 0; i < file.files.length; ++i) {
	  this._images.push({
	    type: "new",
	    file: file.files[i],
	    display_name: file.files[i].fileName,
	    id: "new" + this._autoid++,
	    alt: "",
	    description: "",
	    name: ""
	  });
	}
      }
      else {
	this._images.push({
	  type: "new",
	  file: file,
	  display_name: file.value,
	  id: "new" + this._autoid,
	  alt: "",
	  description: "",
	  name: ""
	});
	++this._autoid;
      }
      this._populate_images();
      this._make_sortable();

      this._file_input = this._make_file_input();
      file.replace(this._file_input);
    }
  },
  _undo_save: function() {
    this._undo_history.push({
      images: this._images.clone(),
      deleted: this._deleted.clone()
    });
  },
  _undo: function() {
    if (this._undo_history.length > 0) {
      var entry = this._undo_history.pop();
      this._images = entry.images;
      this._deleted = entry.deleted;
      this._populate_images();
      this._make_sortable();
    }
  },
  _populate_images: function() {
    this._images_element.update();
    this._images.each(function(im) {
      this._images_element.appendChild(this._make_image_element(im));
    }.bind(this));

    if (BSEAPI.can_drag_and_drop()) {
      var targ = new Element("div", {
	className: this.options.drop_target_class
      });
      targ.update("Drop here");
      BSEAPI.make_drop_zone({
	element: targ,
	onDrop: function(targ, files) {
	  for (var i = 0; i < files.length; ++i) {
	    this._images.push({
	      type: "new",
	      file: files[i],
	      display_name: files[i].fileName,
	      id: "new" + this._autoid,
	      alt: "",
	      description: "",
	      name: ""
	    });
	    ++this._autoid;
	    this._populate_images();
	    this._make_sortable();
	  }
	}.bind(this, targ)
      });
      this._images_element.appendChild(targ);
    }
  },
  _make_sortable: function() {
    Sortable.create(this._images_element.identify(), {
      tag: "div",
      only: this.options.image_entry_class,
      constraint: "horizontal",
      overlap: "horizontal",
      onUpdate: function() {
      }.bind(this)
    });
  },
  _make_image_element: function(im) {
    var p = new Element("div", {
      id: "bse_image_"+im.id,
      className: this.options.image_entry_class
    });
    p.appendChild(this._make_thumb_img(im));
    var del = new Element("span", {
      className: "widget delete"
    });
    del.update("Delete");
    del.observe("click", this._delete_image.bind(this, im));
    p.appendChild(del);
    var edit = new Element("span", {
      className: "widget edit"
    });
    edit.update("Edit");
    edit.observe("click", this._edit_image.bind(this, im));
    p.appendChild(edit);
    var namep = new Element("span", {
      className: "name"
    });
    
    namep.update(im.display_name);
    p.appendChild(namep);

    return p;
  },
  _make_thumb_img: function(im) {
    if (im.thumb_img)
      return im.thumb_img;

    if (im.type == "old") {
      if (this.options.getThumbURL) {
	var img = new Element("img");
	img.src = this.options.getThumbURL(im.image);
	im.thumb_img = img;
      }
      else {
	var thumb = new BSEDialog.ImagePlaceholder({
	  url: im.image.src
	});
	im.thumb_img = thumb.element();
      }
    }
    else {
      var thumb = new BSEDialog.ImagePlaceholder({
	file: im.file
      });
      im.thumb_img = thumb.element();
    }

    return im.thumb_img;
  },
  _delete_image: function(im) {
    this._undo_save();
    if (im.type == "old")
      this._deleted.push(im);
    this._images = this._images.without(im);
    this._populate_images();
    this._make_sortable();
  },
  _edit_image: function(im) {
    new BSEDialog({
      title: "Edit Gallery Image",
      modal: true,
      submit: "Update",
      cancel: true,
      fields: [
	{
	  name: "image",
	  type: "image",
	  value: im,
	  label: "Image"
	}
      ],
      onSubmit: function(im, dlg) {
	var result = dlg.field("image").object();
	im.changed = true;
	im.name = result.name;
	im.alt = result.alt;
	im.description = result.description;
	if (result.file) {
	  im.file = result.file;
	  var thumb = new BSEDialog.ImagePlaceholder({
	    file: im.file
	  });
	  im.thumb_img = thumb.element();
	}
	this._populate_images();
	this._make_sortable();
	dlg.close();
      }.bind(this, im)
    });
  },
  default_options: function($super) {
    return Object.extend(
      Object.extend({}, $super()), {
	value: [],
	image_list_class: "bse_gallery_imagelist",
	image_entry_class: "bse_gallery_image",
	drop_target_class: "bse_drop_target",
	file_input_label: "Add image"
      });
  },
  elements: function () {
    return [ this._element ];
  },
  value: function() {
    return this._images.length > 0 ? "1" : "";
  },
  has_value: function() {
    return this._value.length != 0;
  },
  object: function() {
    return {
      images: this._images,
      deleted: this._deleted
    };
  },
  rules: function() {
    return [];
  },
  inDocument: function() {
    this._make_sortable();
  }
});

BSEDialog.AskYN = Class.create({
  initialize: function(options) {
    this.options = Object.extend({
      submit: "Yes",
      cancel: true,
      cancel_text: "No",
      cancel_class: "rosy",
      modal: true
    }, options);
    this.options.fields = [
      {
	type: "help",
	helptext: options.text
      }
    ];
    if (this.options.onYes)
      this.options.onSubmit = this.options.onYes;
    if (this.options.onNo)
      this.options.onCancel = this.options.onNo;
    var dlg = new BSEDialog(this.options);
  }
});

BSEDialog.ProgressBar = Class.create({
  initialize: function() {
    this._progress = new Element("span", {
      className: "progress"
    });
    this._progress.hide();
    this._progress_status = new Element("span", {
      className: "status"
    });
    this._progress.appendChild(this._progress_status);
    this._progress_bar = new Element("span", {
      className: "bar blue"
    });
    this._progress.appendChild(this._progress_bar);
  },
  element: function() {
    return this._progress;
  },
  start: function(note) {
    if (note != null)
      this.note(note);
    else
      this._progress_status.update();
    this._progress.show();
    this._progress_width = this._progress.getWidth();
    this._progress_bar.style.width = "0px";
  },
  progress: function(frac, note) {
    if (frac != null) {
      this._progress_bar.style.width = Math.floor(this._progress_width * frac) + "px";
    }
    if (note != null)
      this.note(note);
    
  },
  end: function() {
    this._progress.hide();
  },
  note: function(note) {
    if (note != null)
      this._progress_status.update(note);
    else
      this._progress_status.update();
  }
});

BSEDialog.ImagePlaceholder = Class.create({
  initialize:function(options) {
    this.options = Object.extend(this.default_options(), options);

    this._element = new Element("img", {
      width: this.options.width,
      height: this.options.height
    });

    if (this.options.url) {
      this._update(this.options.url);
      return;
    }

    var file = options.file.files ? options.file.files[0] : options.file;
    if (window.URL && window.URL.createObjectURL) {
      this._update(window.URL.createObjectURL(file));
    }
    else if (window.URL && window.webkitURL.createObjectURL) {
      this._update(window.webkitURL.createObjectURL(file));
    }
    else if (window.FileReader) {
      var fr = new FileReader;
      fr.onload = function(fr) {
	this._update(fr.result);
      }.bind(this, fr);
      fr.readAsDataURL(file);
    }
    else {
      this._src = this.options.noapisrc;
      this._element.src = this._src;
      this._onload();
    }
  },
  _update: function(url) {
    var img = new Element("img");
    img.onload = function(img) {
      var canvas = new Element("canvas", {
	width: this.options.width,
	height: this.options.height
      });

      var ctx = canvas.getContext("2d");
      var max_dim = img.width > img.height ? img.width : img.height;
      var scale = this.options.width / max_dim;
      var sc_width = img.width * scale;
      var sc_height = img.height * scale;
      var off_x = (this.options.width - sc_width)/2;
      var off_y = (this.options.height - sc_height)/2;
      ctx.drawImage(img, off_x, off_y, this.options.width-off_x*2, this.options.height-off_y*2);
      this._src = canvas.toDataURL();
      this._element.src = this._src;
      this._onload();
    }.bind(this, img);
    img.src = url
  },
  _onload: function() {
    if (this.options.onLoad)
      this.options.onLoad(this);
  },
  element: function() {
    return this._element;
  },
  // only valid once the image is loaded
  src: function() {
    return this._src;
  },
  default_options: function() {
    return {
      width: 80,
      height: 80,
      noapisrc: "/images/ph.gif"
    };
  }
});
