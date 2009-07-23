// modifies scriptaculous in minor ways
Ajax.InPlaceEditor.prototype.__enterEditMode = Ajax.InPlaceEditor.prototype.enterEditMode;
Object.extend(Ajax.InPlaceEditor.prototype, {
  enterEditMode:function(e) {
    this.__enterEditMode(e);
    if (this.options.maxlength) {
      this._controls.editor.maxLength = this.options.maxlength;
    }
    this.triggerCallback('onFormReady',this._form);
  }
});
