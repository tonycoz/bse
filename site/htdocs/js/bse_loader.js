var BSELoader = Class.create({
  initialize: function(options) {
    this.options = Object.extend({}, options);
    this._scripts = options.scripts.clone();
    this._load_next_script();
  },
  _load_next_script: function() {
    var uri = this._scripts.shift();
    if (BSELoader.cache_buster) {
      uri = uri + "?" + Math.random();
    }
    var scr = new Element("script", { src: uri, type: "text/javascript" });
    scr.loadDone = false;
    scr.onload = function(scr) {
      if (!this.loadDone) {
	scr.loadDone = true;
	this._script_loaded();
      }
    }.bind(this, scr);
    scr.onreadystatechange = function(scr) {
      if ((scr.readyState === "loaded" || scr.readyState === "complete")
	  && !scr.loadDone) {
	scr.loadDone = true;
	this._script_loaded();
      }
    }.bind(this, scr);
    var head = $$("head")[0];
    head.appendChild(scr);
  },
  _script_loaded: function() {
    if (this._scripts.length) {
      this._load_next_script();
    }
    else {
      if (this.options.onLoaded != null)
	this.options.onLoaded();
    }
  }
});

BSELoader.cache_buster = false;