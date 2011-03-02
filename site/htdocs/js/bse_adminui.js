var BSEAdminUI = Class.create
({
   initialize: function() {
     this.handlers = new Hash();
     this._scripts = [];
     this._log = [];
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
     // make something active
   _select: function(what) {
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
   order: function() { alert("Missing order implmentation"); }
 });

document.observe
("dom:loaded",
 function() {
     ui = new BSEAdminUI();
 }
);
