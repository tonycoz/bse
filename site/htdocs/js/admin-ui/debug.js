var BSEDebugUI = Class.create
(BSEUIBase,
{
  start: function(ui, div, args) {
    div.innerHTML = "";
    this._log = new Element("div", { id: "debug_log" });
    div.appendChild(this._log);
    this._load_log(ui);
    this.display(ui, div);
  },
  display: function(ui, div) {
    this._timer = setInterval(this._load_log.bind(this, ui), 1000);
  },
  undisplay: function(ui, div) {
    clearInterval(this._timer);
  },
  needed_content: function(ui, args) {
    return { };
  },
  logon: function() { return false; },
  _load_log: function(ui) {
    this._log.innerHTML = "";
    for (var i = 0; i < ui._log.length; ++i) {
      var entry = new Element("div");
      entry.appendChild(document.createTextNode(ui._log[i]));
      this._log.appendChild(entry);
    }
  }
});

ui.menu_item({
  name: "debug",
  object: new BSEDebugUI(),
  text: "Debug",
  order: "zzzz",
  logon: false
});