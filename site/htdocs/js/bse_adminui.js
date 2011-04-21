
var base_logon_fields =
  [
    {
      name: "logon",
      label: "Logon",
      required: true
    },
    {
      name: "password",
      label: "Password",
      required: true,
      type: "password"
    }
  ];

var BSEAdminUI = Class.create({
  initialize: function() {
    this._log = [];
    this.api = new BSEAPI({onConfig: this._post_start.bind(this)});
    this._messages = new BSEAdminUI.Messages("message");
    this._modules = new Hash();
    this._loaded_scripts = new Hash();
    this._menubar = new BSEMenuBar({});
  },
  register: function (options) {
    var mod = this._modules.get(options.name);
    if (mod) {
      mod.object = options.object;
      mod.options = Object.extend(
	Object.extend({}, this.module_defaults()),
	options);
    }
    else {
      this._log_entry("Attempt to register unknown module " + options.name);
    }
  },
  module_defaults: function() {
    return {
      logon: true
    };
  },
  add_menu: function(name, menu) {
    var mod = this._modules.get(name);
    if (mod) {
      this._menubar.add_menu(menu);
      mod.menus.push(menu);
      if (this.current === mod) {
	$("nav").appendChild(menu.element());
	menu.inDocument();
      }
    }
    else {
      this._log_entry("Attempt to register menu with unknown module " + name);
    }
  },
  // menu_item: function(options) {
  //   options = Object.extend(Object.extend({}, BSEAdminUI.MenuDefaults), options);
  //   this.handlers.set(
  //     options.name,
  //     { 
  // 	options: options,
  // 	key: options.name,
  // 	value: options.object,
  // 	started: false,
  // 	div: null,
  // 	suboptions: new Hash
  //     });
  // },
  // submenu_item: function(options) {
  //   options = Object.extend(Object.extend({}, BSEAdminUI.MenuDefaults), options);
  //   this.handlers.get(options.parent).
  //     set(options.name,
  // 	  {
  // 	    options: options,
  // 	    key: options.name,
  // 	    value: options.object,
  // 	    started: false,
  // 	    div: null
  // 	  });
  // },
  //start: function() {},
  //_bind_static_events: function() {
  //  $("base_logon").observe("click", this._do_logoff.bindAsEventListener(this));
  //  $("base_change_password").observe("click", this._do_changepw.bindAsEventListener(this));
  //},
  _post_start: function() {
    if (this.api.conf.access_control != 0)
      this._make_logon_menu();
    // each line is 
    // text;script;sortorder
    var ui_conf = this.api.conf.admin_ui;
    var menu_items = [];
    for (var i in ui_conf) {
      var entry = ui_conf[i].split(/;/);
      menu_items.push({
	id: "base_menu_item_" + i,
	text: entry[0],
	_order: entry[2],
	onClick: this._select.bind(this, { select: i, rest: ""})
      });
      this._modules.set(i, {
	title: entry[0],
	script: entry[1],
	name: i,
	loaded: false,
	div: null,
	object: null,
	menus: []
      });
    }
    menu_items.sort(function(a, b) {
      return a._order < b._order ? -1 : a._order > b._order ? 1 : 0;
    });

    this._menu_items = menu_items;
    this._main_menu = new BSEMenu({
      title: menu_items[0].text,
      current: true,
      items: menu_items
    });
    $("nav").appendChild(this._main_menu.element());
    this._menubar.add_menu(this._main_menu);

    var sel = this._parse_frag(window.location.hash);
    this._select(sel);
  },
  _make_logon_menu: function() {
    this._logon_menu = new BSEMenu({
      title: "(none)",
      current: true,
      items: [
	{
	  id: "base_menu_user_logout",
	  text: "Logoff",
	  onClick: this._do_logoff.bind(this)
	},
	{
	  id: "base_menu_user_changepw",
	  text: "Change password",
	  onClick: this._do_changepw.bind(this)
	}
      ]
    });
    $("nav").appendChild(this._logon_menu.element());
    this._menubar.add_menu(this._logon_menu);
  },
  // _finish_load: function() {
  //   this._log_entry("Scripts loaded, proceeding");
  //   this._order_handlers();
  //   this._load_menu();
  //   var sel = this._parse_frag(window.location.hash);
  //   this._select(sel);
  //   $("base_wrapper").removeClassName("hide");
  //   $("base_loading").style.display = "none";
  // },
  // _load_scripts: function() {
  //   var ui_conf = this.api.conf.admin_ui;
  //   var to_load = new Array;
  //   for (var i in ui_conf) {
  //     to_load.push(ui_conf[i]);
  //   }
  //   this._log_entry("Loading configured scripts " + to_load.join(" "));
  //   new BSELoader({ scripts: to_load,
  // 		    onLoaded: this._finish_load.bind(this) });
  // },
  load_css: function(css) {
    css.each(function (e) {
      var sty = new Element("link", { rel: "stylesheet", type: "text/css", href: e });
      var head = $$("head")[0];
      head.appendChild(sty);
    });
  },
  // _order_handlers: function() {
  //   // make an ordered list of the registered handlers
  //   // first a name / object list
  //   var list = this.handlers.values();
  //   list.sort(
  //     function (a, b) {
  // 	var aord = a.options.order;
  // 	var bord = b.options.order;
  // 	return aord < bord ? -1 : aord > bord ? 1 : 0;
  //     });
  //   this.ordered = list;
  // },
  // _load_menu: function() {
  //   var menu = $("base_menu");
  //   menu.innerHTML = "";
  //   this.ordered.each(
  //     function(menu, e) {
  // 	var a = new Element("a", { href: "#" + e.key, id: "base_menu_item_"+ e.key });
  // 	a.update(e.options.text);
  // 	a.observe("click", function(e, event) {
  // 	  this._select({ select: e, rest: ""});
  // 	  event.stop();
  // 	  return false;
  // 	}.bind(this, e));
  // 	menu.appendChild(a);
  //     }.bind(this, menu)
  //   );
  // },
  // parse location (or the default "menu") to find something to display
  _parse_frag: function(frag) {
    if (!frag) frag = "#menu";
    frag = frag.replace(/^\#/, '');
    var m = /^([a-z0-9]+)(?:\/(.*))?$/.exec(frag);
    if (m &&
	this._modules.get(m[1]) != null) {
      var rest = m[2] == null ? "" : m[2];

      return { select: m[1], rest: rest };
    }
    else {
      return { select: "menu", rest: "" };
    }
  },
  // make something active, requiring a logon if the view 
  // requires it, which most do
  _select: function(what) {
    var mod = this._modules.get(what.select);
    if (mod == null) {
      this._log_entry("attempt to select unknown " + what.select);
      return;
    }
    if (!mod.loaded) {
      var loader = new BSELoader({
	scripts: [ mod.script ],
	onLoaded: function(what, mod) {
	  mod.loaded = true;
	  if (mod.object) {
	    this._select(what);
	  }
	  else {
	    this._log_entry("Loaded " + what.select + " but no object registered");
	  }
	}.bind(this, what, mod)
      });
    }
    if (!mod.object)
      return;
    if (mod.options.logon
	&& this.api.conf.access_control != 0) {
      if (this._userinfo) {
	if (this._userinfo.user) {
	  this._do_select(what);
	}
	else {
	  this._do_logon_and_select(what);
	}
      }
      else {
	// get the user info
	this.api.userinfo(
	  {
	    onSuccess: function(what, result) {
	      this._userinfo = result;
	      if (this._userinfo.user)
		this._show_current_logon();
	      // try again
	      this._select(what);
	    }.bind(this, what)
	  }
	);
      }
    }
    else {
      this._do_select(what);
    }
  },
  _select_none: function() {
    if (this.current) {
      this.current.menus.each(function(menu) {
	menu.element().remove();
      });
      this.current.object.undisplay(this, this.current.div);
      this.current.div.style.display = "none";
      this.current = null;
    }
  },
  _do_logon_and_select: function(what) {
    new BSEDialog({
      onSubmit: this._on_logon_submit.bind(this, what),
      fields: [
	{
	  type: "fieldset",
	  legend: "Logon",
	  fields: base_logon_fields,
	},
      ],
      modal: true,
      title: "Administration",
      submit: "Logon",
      submit_class: "blue"
    });
  },
  _on_logon_submit: function(what, dlg) {
    this.api.logon({
      logon: dlg.field("logon").value(),
      password: dlg.field("password").value(),
      onSuccess: function(what, dlg, user) {
	this._userinfo.user = user;
	this._show_current_logon();
	dlg.close();
	this._select(what);
	this.message(user.logon + " successfully logged on");
      }.bind(this, what, dlg),
      onFailure: function(dlg, result) {
	dlg.bse_error(result);
      }.bind(this, dlg)
    });
  },
  // inner make something active
  _do_select: function(what) {
    if (this.current)
      this._select_none();
    var mod = this._modules.get(what.select);
    if (mod.started) {
      mod.object.display(this, what.select.div);
      mod.div.style.display = "block";
    }
    else {
      var id = mod.name.replace(/\W+/g, "-");
      mod.div = new Element("div", { id: "app_"+id });
      mod.object.start(this, mod.div, what.rest);
      $("base_work").appendChild(mod.div);
      mod.started = true;
      this._log_entry("Started "+mod.title);
    }
    mod.menus.each(function(menu) {
      $("nav").appendChild(menu.element());
      menu.inDocument();
    });
    this.current = mod;
    this._main_menu.setText(mod.title);
  },
  _log_entry: function(text) {
    var now = new Date;
    this._log.push(now.toISOString() + " " + text);
    if (this._log.length > 1000)
      this._log.shift();
  },
  _show_current_logon: function() {
    if (this._userinfo.user) {
      var user = this._userinfo.user;
      if (/\S/.test(user.name))
	this._logon_menu.setText(user.name); 
      else
	this._logon_menu.setText(user.logon);
    }
    else {
      this._logon_menu.setText("(none)");
    }
  },
  _do_logoff: function(event) {
    //event.stop();
    //$("base_logon").update("Logging off...");
    this._select_none();
    this.api.logoff({
      onSuccess: function() {
	this._userinfo.user = null;
	this._show_current_logon();
	this._select(this._parse_frag("#menu"));
      }.bind(this),
      onFailure: function(result) {
	this.alert(result.msg);
      }.bind(this)
    });
  },
  _do_changepw: function(event) {
    //event.stop();
    if (!this._userinfo.user)
      return;
    new BSEDialog({
      fields: [
	{
	  name: "oldpassword",
	  label: "Old Password",
	  type: "password",
	  required: true
	},
	{
	  name: "newpassword",
	  label: "New Password",
	  type: "password",
	  required: true
	},
	{
	  name: "confirm",
	  label: "Confirm New Password",
	  type: "password",
	  rules: "confirm:newpassword",
	  required: true
	}
      ],
      modal: true,
      submit: "Change Password",
      title: "Change Password",
      cancel: true,
      onSubmit: function(dlg) {
	this._log_entry("Sending change password");
	this.api.change_password({
	  oldpassword: dlg.field("oldpassword").value(),
	  newpassword: dlg.field("newpassword").value(),
	  onSuccess: function(dlg) {
	    this._log_entry("Successfully changed password");
	    dlg.close();
	    this.message("Password for " + this._userinfo.user.logon + " successfully changed");
	  }.bind(this, dlg),
	  onFailure: function(dlg, result) {
	    dlg.bse_error(result);
	  }.bind(this, dlg)
	});
      }.bind(this)
    });
  },
  alert: function(message) {
    new BSEDialog({
      fields: [
	{
	  type: "help",
	  helptext: message
	}
      ],
      title: "Alert!",
      modal: true,
      submit: "Dismiss",
      //submit_class: "dismiss",
      onSubmit: function(dlg) { dlg.close(); }
    });
  },
  message: function(text) {
    this._messages.message(text);
  },
  busy: function() {
  },
  unbusy: function() {
  }
});

var ui;

var BSEUIBase = Class.create({
  undisplay: function(ui, div) {}
});

BSEAdminUI.MenuDefaults =
  {
    logon: true
  };

document.observe(
  "dom:loaded",
  function() {
    ui = new BSEAdminUI();
  }
);

BSEAdminUI.Messages = Class.create({
  initialize: function(div) {
    this.div = $(div);
    this.div.style.display = "none";
  },
  message: function(text) {
    this.div.update(text);
    Effect.Appear(this.div);
    setTimeout(this._msg_done.bind(this),
	       5000);
  },
  _msg_done: function() {
    Effect.Fade(this.div);
  }
});

// var BSEContentUI = Class.create
// (BSEUIBase,
// {
//   start: function(ui, div, args) {
//     div.innerHTML = "One day I'll do something";
//   },
//     display: function(ui, div) {
//     },
//   needed_content: function(ui, args) {
//     return { menu: "/admin/ui/menu.html" };
//   }
// });

// document.observe("dom:loaded", function() {
//   var handler = new BSEContentUI;
//   ui.menu_item({
//     name: "content",
//     object: handler,
//     text: "Content",
//     order: "b"
//   });
//   ui.menu_item({
//     name: "users",
//     object: handler,
//     text: "Users",
//     order: "c"
//   });
//   ui.menu_item({
//     name: "system",
//     object: handler,
//     text: "System",
//     order: "d"
//   });
  
// });

