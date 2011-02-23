var BSEAdminUI = Class.create
({
   initialize: function() {
     this.api = new BSEAPI({_async: false});
     this.handlers = new Hash();
   },
   load_scripts: function() {
     var ui_conf = this.api.conf.admin_ui;
     for (var i in ui_conf) {
       document.write('<script type="text/javascript" src="' + ui_conf[i] + '"></script>');
       
     }
   },
   register: function(name, obj) {
     this.handlers.set(name, obj);
   },
   start: function() {
     this._order_handlers();
     this._load_menu();
     this._parse_frag();
     this._select();
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
     var menu = $("menu");
     menu.innerHTML = "";
     this.ordered.each
     (
       function(menu, e) {
	 var a = new Element("a", { href: "#" + e.key });
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

document.observe("dom:loaded", ui.start.bind(ui));
