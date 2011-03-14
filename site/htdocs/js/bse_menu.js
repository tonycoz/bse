// represents a top-level menu item
// 
var BSEMenu = Class.create({
  initialize: function(options) {
    this.options = Object.extend(
      Object.extend({}, this.defaults()), options);
    this._make_element();
  },
  // return an element containing the menu
  // this must be an li
  element: function() {
    return this._element;
  },
  _make_element: function() {
    this._element = new Element("li");
    if (this.options.current)
      this._element.addClassName(this.options.current_class);
    this._title_element = new Element("a", { href: "#" });
    this._title_element.observe("click", function(ev) { ev.stop(); });
    this._title_element.update(this.options.title);
    this._element.appendChild(this._title_element);

    // caller provided their own content for the menu
    this._submenu = new this.options.submenu_class(this.options);
    this._element.appendChild(this._submenu.element());
  },
  setText: function(text) {
    this._title_element.update(text);
  },
  defaults: function() {
    return BSEMenu.defaults;
  }
});

// an item in a drop-down menu
BSEMenu.Item = Class.create({
  initialize: function(options) {
    this.original_options = options;
    this.options = Object.extend(
      Object.extend({}, this.defaults()), options);
    this._make_element();
    this.original_options.object = this;
  },
  element: function() {
    return this._element;
  },
  submenu: function() {
    return this._submenu;
  },
  setSubmenu: function(submenu) {
    if (this._submenu) {
      this._element.replaceChild(submenu.element(), this._submenu.element());
    }
    else {
      this._element.appendChild(submenu.element());
    }
    this._submenu = submenu;
  },
  defaults: function() {
    return BSEMenu.Item.defaults;
  },
  setChecked: function(checked) {
    if (checked) {
      this._element.removeClassName(this.options.unchecked_class);
      this._element.addClassName(this.options.checked_class);
    }
    else {
      this._element.removeClassName(this.options.checked_class);
      this._element.addClassName(this.options.unchecked_class);
    }
    this._checked = checked;
  },
  checked: function() {
    return this._checked;
  },
  setDisabled: function(disabled) {
    if (disabled) {
      this._element.addClassName(this.options.disabled_class);
    }
    else {
      this._element.removeClassName(this.options.disabled_class);
    }
    this._disabled = disabled;
  },
  disabled: function() {
    return this._disabled;
  },
  setText: function(text) {
    this._link.update(text);
  },
  _make_element: function() {
    this._element = new Element("li");
    this._link = new Element("a", { href: "#" });
    this._link.update(this.options.text);
    this._link.observe("click", this._onclick.bind(this));
    this._element.appendChild(this._link);
    if (this.options.item_class)
      this._element.addClassName(this.options.item_class);
    if (this.options.id)
      this._element.id = this.options.id;

    if (this.options.check)
      this.setChecked(this.options.checked);
    if (this.options.separate)
      this._element.addClassName(this.options.separate_class);
    this.setDisabled(this.options.disabled);

    if (this.options.submenu) {
      this._submenu = new this.options.submenu_class(this.options.submenu);
      this._element.appendChild(this._submenu.element());
    }
  },
  _onclick: function(ev) {
    ev.stop();
    if (!this._disabled && this.options.onClick)
      this.options.onClick(this.original_options);
  }
});

// a drop-down menu, either from the menu bar, or as a submenu of an item
BSEMenu.SubMenu = Class.create({
  initialize: function(options) {
    this.options = Object.extend(
      Object.extend({}, this.defaults()), options);
    this._make_element();
  },
  items: function() {
    return this._items;
  },
  element: function() {
    return this._element;
  },
  _make_element: function() {
    if (this.options.element) {
      this._element = this.options.element;
    }
    else {
      var ele = new Element("ul");
      this._items = [];
      var items = this.options.items;
      for (i = 0; i < items.length; ++i) {
	var item = new this.options.item_class(items[i]);
	ele.appendChild(item.element());
	this._items.push(item);
      }
      this._element = ele;
    }
  },
  defaults: function() {
    return BSEMenu.SubMenu.defaults;
  }
});

BSEMenu.defaults = {
  current: false,
  current_class: "current",
  submenu_class: BSEMenu.SubMenu
};

BSEMenu.SubMenu.defaults = {
  items: [],
  item_class: BSEMenu.Item
};

BSEMenu.Item.defaults = {
  check: false,
  separate: false,
  disabled: false,
  name: "",
  checked_class: "checked",
  unchecked_class: "unchecked",
  separate_class: "separate",
  disabled_class: "disabled",
  submenu_class: BSEMenu.SubMenu
};