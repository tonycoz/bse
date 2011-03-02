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

var BSEAdminUI = Class.create
({
   initialize: function() {
     this.handlers = new Hash();
     this._scripts = [];
     this._log = [];
       this._logged_on = false;
     this.api = new BSEAPI({onConfig: this._post_start.bind(this)});
   },
   register: function(name, obj) {
     this.handlers.set
       (name,
	{ 
	    key: name,
	    value: obj,
	    started: false,
	    div: null
	});
   },
   start: function() {},
   _post_start: function() {
     this._load_scripts();
   },
   _finish_load: function() {
     this._order_handlers();
     this._load_menu();
     var sel = this._parse_frag();
     this._select(sel);
       $("base_wrapper").removeClassName("hide");
       $("base_loading").style.display = "none";
   },
   _script_loaded: function() {
     if (this._scripts.length) {
	 this._load_next_script();
     }
       else {
	   var loader = this._on_script_load;
	   this._on_script_load = null;
	   if (loader)
	       loader();
       }
   },
   _load_scripts: function() {
     var ui_conf = this.api.conf.admin_ui;
     var to_load = new Array;
     for (var i in ui_conf) {
       to_load.push(ui_conf[i]);
     }
     this.load_scripts(to_load, this._finish_load.bind(this));
   },
   load_css: function(css) {
       css.each(function (e) {
		    var sty = new Element("link", { rel: "stylesheet", type: "text/css", href: "e" });
		    var head = $$("head")[0];
		    head.appendChild(scr);
		});
   },
   load_scripts: function(scripts, onLoad) {
       scripts.each(function(a) { this._scripts.push(a); }.bind(this));
       if (onLoad) {
	   this._on_script_load = onLoad;
       }
       if (!this._loading_scripts) {
	   this._load_next_script();
       }
   },
   _load_next_script: function() {
     var uri = this._scripts.shift();
     var scr = new Element("script", { src: uri, type: "text/javascript" });
     scr.loadDone = false;
     scr.onload = function(ui) {
	 if (!this.loadDone) {
	   this.loadDone = true;
           ui._script_loaded();
         }
       }.bind(scr, this);
     scr.onreadystatechange = function(ui) {
       if ((this.readyState === "loaded" || this.readyState === "complete")
           && !this.loadDone) {
         this.loadDone = true;
	 ui._script_loaded();
       }
     }.bind(scr, this);
       this._log_entry("Loading script " + uri);
     var head = $$("head")[0];
     head.appendChild(scr);
   },
   _order_handlers: function() {
     // make an ordered list of the registered handlers
     // first a name / object list
     var list = this.handlers.values();
     list.sort
       (function (a, b) {
	  var aord = a.value.order();
	  var bord = b.value.order();
	  return aord < bord ? -1 : aord > bord ? 1 : 0;
	});
     this.ordered = list;
   },
   _load_menu: function() {
     var menu = $("base_menu");
     menu.innerHTML = "";
     this.ordered.each
     (
       function(menu, e) {
	 var a = new Element("a", { href: "#" + e.key, id: "base_menu_item_"+ e.key });
	 a.update(e.value.menu_text());
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
   _parse_frag: function() {
       var frag = window.location.hash;
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
	 if (what.select.value.logon()
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
		 this.api.userinfo
		 (
		     {
			 onSuccess: function(what, result) {
			     this._userinfo = result;
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
	 new BSEDialog
	 ({
	      onSubmit: this._on_logon_submit.bind(this, what),
	      fields: base_logon_fields,
	      modal: true,
	      title: "Logon"
	  });
     },
     _on_logon_submit: function(what, dlg) {
	 this.api.logon
	 ({
	      logon: dlg.values.logon,
	      password: dlg.values.password,
	      onSuccess: function(what, dlg, user) {
		  this._userinfo.user = user;
		  dlg.close();
		  this._select(what);
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
       $("base_menu_current").update(this.current.value.menu_text());
   },
   _log_entry: function(text) {
       this._log.push(text);
       if (this._log.length > 1000)
	   this._log.shift();
   }
 });

var ui;

var BSEUIBase = Class.create
({
   order: function() { alert("Missing order implmentation"); },
     logon: function() { return true; }
 });

document.observe
("dom:loaded",
 function() {
     ui = new BSEAdminUI();
 }
);

var BSEDialog = Class.create
({
     initialize: function(options) {
	 this.options = Object.extend
	 (
	     {
		 modal: false,
		 title: "Missing title",
		 //validator: new BSEValidator,
		 top_class: "bse_dialog",
		 modal_class: "bse_modal",
		 title_class: "bse_title",
		 error_class: "bse_error",
		 field_wrapper_class: "bse_field_wrapper",
		 field_error_class: "bse_field_error",
		 help_class: "bse_help",
		 submit_wrapper_class: "bse_submit_wrapper",
		 submit: "Submit"
	     },
	     options);
	 this._build();
	 this._show();
     },
     _reset_errors: function() {
     },
     error: function(msg) {
	 this._reset_errors();
	 this._error.update(msg);
	 this._error.style.display = "block";
     },
     field_errors: function(errors) {
	 this._reset_errors();
	 for (var i in errors) {
	     var div = this.field_error_divs[i];
	     if (div) {
		 div.update(errors[i]);
		 div.style.display = "block";
	     }
	 }
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
	 this.form.observe("submit", this._onsubmit.bind(this));
	 this.div.appendChild(this.form);
	 this.field_error_divs = {};
	 this.field_wrapper_divs = {};
	 this.fields = {};
	 this._add_fields(this.form, this.options.fields);
	 var sub_wrapper = new Element("div", { className: this.options.submit_wrapper_class });
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
	     // this.wrapper.style.height = document.viewport.getHeight() + "px";
	     this.wrapper.style.height = "100%";
	 }
     },
     _add_fields: function(parent, fields) {
	 for (var i = 0; i < fields.length; ++i) {
	     var f = Object.extend({
				       type: "text",
				       rows: 10,
				       cols: 40,
				       label: "Missing Label",
				       value: "",
				       values: [ { value: "", label: "No values" }]
				   }, fields[i]);
	     switch (f.type) {
	     case "help":
		 var help = new Element("div");
		 help.update(f.helptext);
		 parent.appendChild(help);
		 break;
	     case "fieldset":
		 var fieldset = new Element("fieldset");
		 if (f.label) {
		     var legend = new Element("legend")
		     legend.update(f.label);
		     fieldset.appendChild(legend);
		 }
		 this._add_fields(fieldset, f.fields);
		 parent.appendChild(fieldset);
		 break;
	     default:
		 parent.appendChild(this._build_field(f));
		 break;
	     }
	 }
     },
     _build_field: function(f) {
	 var wrapper = new Element("div", { className: this.options.field_wrapper_class });
	 var label = new Element("label");
	 label.update(f.label);
	 wrapper.appendChild(label);

	 switch (f.type) {
	 case "textarea":
	     var input = new Element("textarea", { name: f.name, value: f.value, cols: f.cols, rows: f.rows });
	     this.fields[f.name] = input;
	     wrapper.appendChild(input);
	     break;

	 case "select":
	     var input = new Element("select", { name: f.name });
	     for (var i = 0; i < f.values.length; ++i) {
		 var val = f.values[i];
		 var def = f.value != null && f.value == val.key;
		 input.options[input.options.length] =
		     new Option(val.label, val.value, def);
	     }
	     this.fields[f.name] = input;
	     wrapper.appendChild(input);
	     break;
	     
	 default:
	     var input = new Element("input", { name: f.name, type: f.type, value: f.value });
	     wrapper.appendChild(input);
	     this.fields[f.name] = input;
	     break;
	 }
	 var error = new Element("div", { className: this.options.field_error_class });
	 error.style.display = "none";
	 wrapper.appendChild(error);
	 this.field_wrapper_divs[f.name] = wrapper;
	 this.field_error_divs[f.name] = error;

	 return wrapper;
     },
     _onsubmit: function(event) {
	 event.stop();
	 var values = new Object;
	 for (var i in this.fields) {
	     values[i] = this.fields[i].value;
	 }
	 this.values = values;
	 this.options.onSubmit(this);
     }
});
