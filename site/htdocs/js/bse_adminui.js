var BSEAdminUI = Class.create
({
   initialize: function() {
     this.handlers = new Hash();
     this._scripts = [];
     this._log = [];
     this.api = new BSEAPI({onConfig: this._post_start.bind(this)});
   },
   register: function(name, obj) {
     this.handlers.set(name, obj);
   },
   start: function() {},
   _post_start: function() {
     this._load_scripts();
   },
   _finish_load: function() {
     this._order_handlers();
     this._load_menu();
     this._parse_frag();
     this._select();
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
     var head = $$("head")[0];
     head.appendChild(scr);
   },
   _order_handlers: function() {
     // make an ordered list of the registered handlers
     // first a name / object list
     var list = this.handlers.map
     (function(e) { return { key: e.key, value: e.value }; });
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
	 menu.appendChild(a);
       }.bind(this, menu)
     );
   },
   _parse_frag: function() {
   },
   _select: function() {
   }
 });

var ui = new BSEAdminUI();

var BSEUIBase = Class.create
({
   order: function() { alert("Missing order implmentation"); }
 });

//document.observe("dom:loaded", ui.start.bind(ui));
