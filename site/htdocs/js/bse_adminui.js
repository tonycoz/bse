
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
    this.handlers = new Hash();
    this._scripts = [];
    this._log = [];
    this._logged_on = false;
    this._bind_static_events();
    this.api = new BSEAPI({onConfig: this._post_start.bind(this)});
    this._messages = new BSEAdminUI.Messages("base_messages");
  },
  menu_item: function(options) {
    options = Object.extend(Object.extend({}, BSEAdminUI.MenuDefaults), options);
    this.handlers.set(
      options.name,
      { 
	options: options,
	key: options.name,
	value: options.object,
	started: false,
	div: null,
	suboptions: new Hash
      });
  },
  submenu_item: function(options) {
    options = Object.extend(Object.extend({}, BSEAdminUI.MenuDefaults), options);
    this.handlers.get(options.parent).
      set(options.name,
	  {
	    options: options,
	    key: options.name,
	    value: options.object,
	    started: false,
	    div: null
	  });
  },
  start: function() {},
  _bind_static_events: function() {
    $("base_logon").observe("click", this._do_logoff.bindAsEventListener(this));
    $("base_change_password").observe("click", this._do_changepw.bindAsEventListener(this));
  },
  _post_start: function() {
    this._load_scripts();
  },
  _finish_load: function() {
    this._log_entry("Scripts loaded, proceeding");
    this._order_handlers();
    this._load_menu();
    var sel = this._parse_frag(window.location.hash);
    this._select(sel);
    $("base_wrapper").removeClassName("hide");
    $("base_loading").style.display = "none";
  },
  _load_scripts: function() {
    var ui_conf = this.api.conf.admin_ui;
    var to_load = new Array;
    for (var i in ui_conf) {
      to_load.push(ui_conf[i]);
    }
    this._log_entry("Loading configured scripts " + to_load.join(" "));
    new BSELoader({ scripts: to_load,
		    onLoaded: this._finish_load.bind(this) });
  },
  load_css: function(css) {
    css.each(function (e) {
      var sty = new Element("link", { rel: "stylesheet", type: "text/css", href: "e" });
      var head = $$("head")[0];
      head.appendChild(scr);
    });
  },
  _order_handlers: function() {
    // make an ordered list of the registered handlers
    // first a name / object list
    var list = this.handlers.values();
    list.sort(
      function (a, b) {
	var aord = a.options.order;
	var bord = b.options.order;
	return aord < bord ? -1 : aord > bord ? 1 : 0;
      });
    this.ordered = list;
  },
  _load_menu: function() {
    var menu = $("base_menu");
    menu.innerHTML = "";
    this.ordered.each(
      function(menu, e) {
	var a = new Element("a", { href: "#" + e.key, id: "base_menu_item_"+ e.key });
	a.update(e.options.text);
	a.observe("click", function(e, event) {
	  this._select({ select: e, rest: ""});
	  event.stop();
	  return false;
	}.bind(this, e));
	menu.appendChild(a);
      }.bind(this, menu)
    );
  },
  // parse location (or the default "menu") to find something to display
  _parse_frag: function(frag) {
    if (!frag) frag = "#menu";
    frag = frag.replace(/^\#/, '');
    var selname = "";
    var rest = "";
    var sel = null;
    for (var i = 0; i < this.ordered.length; ++i) {
      var e = this.ordered[i];
      if (frag.substr(0, e.key.length) == e.key
	  && /^(\/|$)/.match(frag.substr(e.key.length))
	  && e.key.length > selname.length) {
	sel = e;
	rest = frag.substr(e.key.length);
	selname = e.key;
      }
    }
    if (sel == null) {
      this._log_entry("No entry found for " + frag);
      sel = this.ordered[0];
      rest = "";
    }
    return { select: sel, rest: rest };
  },
  // make something active, requiring a logon if the view 
  // requires it, which most do
  _select: function(what) {
    if (what.select.options.logon
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
  _do_logon_and_select: function(what) {
    new BSEDialog({
      onSubmit: this._on_logon_submit.bind(this, what),
      fields: base_logon_fields,
      modal: true,
      title: "Logon"
    });
  },
  _on_logon_submit: function(what, dlg) {
    this.api.logon({
      logon: dlg.values.logon,
      password: dlg.values.password,
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
      this.current.div.style.display = "none";
    if (what.select.started) {
      what.select.value.display(this, what.select.div);
      what.select.div.style.display = "block";
    }
    else {
      var id = what.select.key.replace(/\W+/g, "-");
      what.select.div = new Element("div", { id: id });
      what.select.value.start(this, what.select.div, what.rest);
      $("base_work").appendChild(what.select.div);
      what.select.started = true;
      this._log_entry("Started "+what.select.key);
    }
    this.current = what.select;
    $("base_menu_current").update(this.current.options.text);
  },
  _log_entry: function(text) {
    var now = new Date;
    this._log.push(now.toISOString() + " " + text);
    if (this._log.length > 1000)
      this._log.shift();
  },
  _show_current_logon: function() {
    var div = $("base_logon");
    if (this._userinfo.user) {
      div.update("Logoff " + this._userinfo.user.logon);
      div.style.display = "block";
    }
    else {
      div.update("");
      div.style.display = "none";
    }
  },
  _do_logoff: function(event) {
    event.stop();
    this._select(this._parse_frag("#menu"));
    $("base_logon").update("Logging off...");
    this.api.logoff({
      onSuccess: function() {
	var div = $("base_logon");
	div.update("");
	div.style.display = "none";
	this._userinfo.user = null;
      }.bind(this),
      onFailure: function(result) {
	this.alert(result.msg);
      }.bind(this)
    });
  },
  _do_changepw: function(event) {
    event.stop();
    if (!this._userinfo.user)
      return;
    new BSEDialog({
      fields: [
	{
	  name: "old",
	  label: "Current Password",
	  type: "password",
	  required: true
	},
	{
	  name: "password",
	  label: "New Password",
	  type: "password",
	  required: true
	},
	{
	  name: "confirm",
	  label: "Confirm",
	  type: "password",
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
	  oldpassword: dlg.values.old,
	  newpassword: dlg.values.password,
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
	  type: help,
	  helptext: message
	}
      ],
      title: "Alert!",
      modal: true,
      submit: "Dismiss",
      top_class: "bse_title bse_alert",
      onSubmit: function(dlg) { dlg.close(); }
    });
  },
  message: function(text) {
    this._messages.message(text);
  }
});

var ui;

var BSEUIBase = Class.create({
  order: function() { alert("Missing order implmentation"); },
  logon: function() { return true; }
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
  },
  message: function(text) {
    var msg_div = new Element("div", { style: "display: none" });
    var real_div = new Element("div", { className: "message" });
    real_div.update(text);
    msg_div.appendChild(real_div);
    this.div.appendChild(msg_div);
    Effect.BlindDown(msg_div);
    setTimeout(this._msg_done.bind(this, msg_div),
	       5000);
  },
  _msg_done: function(msg_div) {
    Effect.BlindUp(
      msg_div,
      {
       afterFinish: function(msg_div) {
	 msg_div.remove();
       }.bind(this, msg_div)
     });
  }
});

var BSEContentUI = Class.create
(BSEUIBase,
{
  start: function(ui, div, args) {
    div.innerHTML = "One day I'll do something";
  },
    display: function(ui, div) {
    },
  needed_content: function(ui, args) {
    return { menu: "/admin/ui/menu.html" };
  }
});

document.observe("dom:loaded", function() {
  var handler = new BSEContentUI;
  ui.menu_item({
    name: "content",
    object: handler,
    text: "Content",
    order: "b"
  });
  ui.menu_item({
    name: "users",
    object: handler,
    text: "Users",
    order: "c"
  });
  ui.menu_item({
    name: "system",
    object: handler,
    text: "System",
    order: "d"
  });
  
});

