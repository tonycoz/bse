var prodopts_by_id = new Object;
var menu;

/*
 I got sick of Prototype eating real errors, so now I always capture
 and display them.
 */
function handle_exception(obj, e) {
  alert("Exception: " + e);
}

function reorder_option_values(opt_id, order) {
  var parent = $("vallist"+opt_id);
  var nodes = new Array;
  var nodes_by_id = new Object;
  for (var i = 0; i < parent.childNodes.length; ++i) {
    var n = parent.childNodes[i];
    if (n.id) {
      var m = n.id.match(/^valentry(\d+)$/);
      if (m) {
        nodes_by_id[m[1]] = n;
        nodes.push(n);
      }
    }
  }
  // remove our value nodes
  for (var i = 0; i < nodes.length; ++i) {
    parent.removeChild(nodes[i]);
  }
  // put them back in, in the new order
  for (var i = 0; i < order.length; ++i) {
    var n = nodes_by_id[order[i]];
    if (n)
      parent.appendChild(n);
  }

  var vals = prodopts_by_id[opt_id].values;
  var vals_by_id = new Object;
  for (var i = 0; i < vals.length; ++i) {
    vals_by_id[vals[i].id] = vals[i];
  }
  var new_vals = new Array;
  for (var i = 0; i < order.length; ++i) {
    new_vals.push(vals_by_id[order[i]]);
  }
  prodopts_by_id[opt_id].values = new_vals;

  fix_prodoptval_order_tools(prodopts_by_id[opt_id]);
}

function reorder_options(order) {
  var parent = $("productoptions");
  var nodes = new Array;
  var nodes_by_id = new Object;
  for (var i = 0; i < parent.childNodes.length; ++i) {
    var n = parent.childNodes[i];
    if (n.id) {
      var m = n.id.match(/^prodopt(\d+)$/);
      if (m) {
        nodes_by_id[m[1]] = n;
        nodes.push(n);
      }
    }
  }
  // remove our value nodes
  for (var i = 0; i < nodes; ++i) {
    parent.removeChild(nodes[i]);
  }
  // put them back in, in the new order
  for (var i = 0; i < order.length; ++i) {
    var n = nodes_by_id[order[i]];
    if (n)
      parent.appendChild(n);
  }

  prodopts = new Array();
  for (var i = 0; i < order.length; ++i) {
    prodopts.push(prodopts_by_id[order[i]]);
  }

  fix_prodopt_order_tools();
}

function reorder_values(option_id, order) {
  var parent = $("vallist"+option_id);
  var nodes = new Array;
  var nodes_by_id = new Object;
  for (var i = 0; i < parent.childNodes.length; ++i) {
    var n = parent.childNodes[i];
    if (n.id) {
      var m = n.id.match(/^valentry(\d+)$/);
      if (m) {
        nodes_by_id[m[1]] = n;
        nodes.push(n);
      }
    }
  }
  // remove our value nodes
  for (var i = 0; i < nodes; ++i) {
    parent.removeChild(nodes[i]);
  }
  // put them back in, in the new order
  for (var i = 0; i < order.length; ++i) {
    var n = nodes_by_id[order[i]];
    if (n)
      parent.appendChild(n);
  }

  var opt = prodopts_by_id[option_id];
  var vals_by_id = new Object;
  for (var i = 0; i < opt.values.length; ++i) {
    vals_by_id[opt.values[i].id] = opt.values[i];
  }
  opt.values = new Array;
  for (var i = 0; i < order.length; ++i) {
    opt.values.push(vals_by_id[order[i]]);
  }

  fix_prodoptval_order_tools(opt);
}

function do_option_move(key, id) {
  set_busy("prodoptmove"+id);
  var parm = {
      id: article_id,
      option_id: id,
      _csrfp: reorder_options_csrf,
      _: 1
    };
  parm[key] = 1;
  new Ajax.Request(edit_script, {
    method: "post",
    parameters: parm,
    onSuccess: function(xport) {
      var json = xport.responseJSON;
      set_not_busy("prodoptmove"+id);
      if (json && json.success) {
        reorder_options(json.order);
      }
      else {
        show_response_error("reordering options", xport);
      }
    },
    onFailure: function(xport) {
      set_not_busy("prodoptmove"+id);
      show_response_error("reordering options", xport);
    },
    onException: handle_exception
    });
}

function prodopt_move_up(id) {
  do_option_move('a_option_moveup', id);
}

function prodopt_move_down(id) {
  do_option_move('a_option_movedown', id);
}

// fix the arrows mostly
function fix_prodopt_order_tools() {
  for (var i = 0; i < prodopts.length; ++i) {
    var opt = prodopts[i];
    var move_ele = $('prodoptmove'+opt.id);
    if (move_ele) {
      // remove all the kids
      while (move_ele.firstChild != null) {
        move_ele.removeChild(move_ele.firstChild);
      }
    }
    if (i != prodopts.length-1) {
      var move_down = new Element("a");
      move_down.href="javascript:prodopt_move_down("+opt.id+")";
      var down_img = new Element("img");
      down_img.src = "/images/admin/move_down.gif";
      move_down.appendChild(down_img);
      move_ele.appendChild(move_down);
    }
    else {
      var empty = new Element('img');
      empty.src = "/images/trans_pixel.gif";
      move_ele.appendChild(empty);
    }
    if (i != 0) {
      var move_up = new Element("a");
      move_up.href="javascript:prodopt_move_up("+opt.id+")";
      var up_img = new Element("img");
      up_img.src = "/images/admin/move_up.gif";
      move_up.appendChild(up_img);
      move_ele.appendChild(move_up);
    }
    else {
      var empty = new Element('img');
      empty.src = "/images/trans_pixel.gif";
      move_ele.appendChild(empty);
    }
  }
}

function do_value_move(key, opt_id, id) {
  set_busy("prodoptvaluemove"+id);
  var parm = {
      id: article_id,
      option_id: opt_id,
      value_id: id,
      _csrfp: reorder_values_csrf,
      _: 1
    };
  parm[key] = 1;
  new Ajax.Request(edit_script, {
    method: "post",
    parameters: parm,
    onSuccess: function(xport) {
      var json = xport.responseJSON;
      set_not_busy("prodoptvaluemove"+id);
      if (json && json.success) {
        reorder_option_values(opt_id, json.order);
      }
      else {
        show_response_error("reordering values", xport);
      }
    },
    onFailure: function(xport) {
      set_not_busy("prodoptvaluemove"+id);
      show_response_error("reordering values", xport);
    },
    onException: handle_exception
    });
}

function prodoptval_move_up(opt_id, id) {
  do_value_move('a_option_value_moveup', opt_id, id);
}

function prodoptval_move_down(opt_id, id) {
  do_value_move('a_option_value_movedown', opt_id, id);
}

function fix_prodoptval_order_tools(opt) {
  var vals = opt.values;
  for (var i = 0; i < vals.length; ++i) {
    var val = vals[i];
    var val_ele = $('valentry'+val.id);
    val_ele.removeClassName("odd");
    if (i % 2 == 1)
      val_ele.addClassName("odd");
    var move_ele = $('prodoptvaluemove'+val.id);
    if (move_ele) {
      // remove all the kids
      while (move_ele.firstChild != null) {
        move_ele.removeChild(move_ele.firstChild);
      }
    }
    if (i != vals.length-1) {
      var move_down = new Element("a");
      move_down.href="javascript:prodoptval_move_down("+opt.id+","+val.id+")";
      var down_img = new Element("img");
      down_img.src = "/images/admin/move_down.gif";
      move_down.appendChild(down_img);
      move_ele.appendChild(move_down);
    }
    else {
      var empty = new Element('img');
      empty.src = "/images/trans_pixel.gif";
      move_ele.appendChild(empty);
    }
    if (i != 0) {
      var move_up = new Element("a");
      move_up.href="javascript:prodoptval_move_up("+opt.id+","+val.id+")";
      var up_img = new Element("img");
      up_img.src = "/images/admin/move_up.gif";
      move_up.appendChild(up_img);
      move_ele.appendChild(move_up);
    }
    else {
      var empty = new Element('img');
      empty.src = "/images/trans_pixel.gif";
      move_ele.appendChild(empty);
    }
  }
}

var busy_img;

function set_busy(id) {
  if (busy_img)
    busy_img.style.visibility = 'visible';
}
function set_not_busy(id) {
  if (busy_img)
    busy_img.style.visibility = 'hidden';
}

function sort_prodopt_values(id) {
  var opt = prodopts_by_id[id];

  var ord = new Array;
  // duplicate to sort it
  for (var i = 0; i < opt.values.length; ++i) {
    ord.push(opt.values[i]);
  }
  ord.sort(function(a, b) {
    var va = a.value.toLowerCase();
    var vb = b.value.toLowerCase();
    if (va < vb) return -1;
    if (va > vb) return 1;
    return 0;
  });
  var ids = new Array;
  for (var i = 0; i < ord.length; ++i) {
    ids.push(ord[i].id);
  }
  set_busy();
  new Ajax.Request(edit_script, {
    method: "post",
    parameters: {
      a_option_value_reorder: 1,
      id: article_id,
      option_id: id,
      value_ids: ids.join(","),
      _csrfp: reorder_values_csrf,
      _: 1
    },
    onSuccess: function(xport) {
      var json = xport.responseJSON;
      set_not_busy();
      if (json.success) {
        reorder_option_values(json.option.id, json.order);
      }
      else {
        alert("Error sorting: " + json.error);
      }
    },
    onFailure: function() {
      alert("Error contacting server");
      set_not_busy();
    },
    onException: handle_exception
    });
}

function reorder_prodopts_req(ele_id, ids) {
  set_busy(ele_id);
  new Ajax.Request(edit_script, {
    method: "post",
    parameters: {
      a_option_reorder: 1,
      id: article_id,
      option_ids: ids.join(","),
      _csrfp: reorder_options_csrf,
      _: 1
    },
    onSuccess: function(xport) {
      var json = xport.responseJSON;
      set_not_busy(ele_id);
      if (json && json.success) {
        reorder_options(json.order);
      }
      else {
        show_response_error("re-ordering options", xport);
      }
    },
    onFailure: function(xport) {
      set_not_busy(ele_id);
      show_response_error("re-ordering options", xport);
    },
    onException: handle_exception
    });
}

function reorder_prodoptvals_req(ele_id, opt_id, ids) {
  set_busy(ele_id);
  new Ajax.Request(edit_script, {
    method: "post",
    parameters: {
      a_option_value_reorder: 1,
      id: article_id,
      option_id: opt_id,
      value_ids: ids.join(","),
      _csrfp: reorder_values_csrf,
      _: 1
    },
    onSuccess: function(xport) {
      var json = xport.responseJSON;
      set_not_busy(ele_id);
      if (json && json.success) {
        reorder_values(opt_id, json.order);
      }
      else {
        show_response_error("re-ordering values", xport);
      }
    },
    onFailure: function(xport) {
      set_not_busy(ele_id);
      show_response_error("re-ordering values", xport);
    },
    onException: handle_exception
    });
}

function sort_prodopts() {
  var ord = new Array;
  for (var i = 0; i < prodopts.length; ++i) {
    ord.push(prodopts[i]);
  }
  ord.sort(function(a, b) {
    var va = a.name.toLowerCase();
    var vb = b.name.toLowerCase();
    if (va < vb) return -1;
    if (va > vb) return 1;
    return 0;
    });
  var ids = new Array;
  for (var i = 0; i < ord.length; ++i) {
    ids.push(ord[i].id);
  }
  reorder_prodopts_req("sortoptions", ids);
}

function reverse_prodopts() {
  var ids = new Array;
  for (var i = 0; i < prodopts.length; ++i) {
    ids.unshift(prodopts[i].id);
  }
  reorder_prodopts_req("reverseoptions", ids);
}

function show_response_error(action, xport) {
  if (xport.responseJSON) {
    if (xport.responseJSON.errors
        && xport.responseJSON.errors._csrfp) {
      alert("Please reload the page, your update tokens may be out of date\n\n"+xport.responseJSON.errors._csrfp);
    }
    else if (xport.responseJSON.message)
       alert("Error "+action+": " + xport.responseJSON.message);
    else
      alert("Unknown error "+action);
  }
  else if (xport.responseText) {
    alert(xport.responseText);
  }
  else
    alert("Unknown error "+action);
}

function prodopt_add_option_ipe(opt) {
    new Ajax.InPlaceEditor("prodoptname"+opt.id, edit_script,
      {
      cancelControl: "button",
      okText: "Save",
      cancelText: "Cancel",
      maxlength: 255,
      callback: function(f, v) {
        return "_=1&_t=prodopts&_csrfp="+ edit_option_csrf +"&id="+article_id+"&a_save_option=1&option_id="+this.id+"&name="+encodeURIComponent(v);
      }.bind(opt),
      onComplete: function(xport) {
        var name_ele = $("prodoptname"+this.id);
        name_ele.innerHTML = "";
        var new_name;
        if (xport
            && xport.status == 200
            && xport.responseJSON
            && xport.responseJSON.success) {
          new_name = xport.responseJSON.option.name;
	  prodopts_by_id[this.id].name = new_name;
          name_ele.appendChild(document.createTextNode(new_name));
        }
        else {
          // restore the original name
          new_name = prodopts_by_id[this.id].name;
          name_ele.appendChild(document.createTextNode(new_name));
          if (xport) {
            if (xport.responseJSON && xport.responseJSON.errors.name) {
              alert("Error saving option name: "
	            + xport.responseJSON.errors.name);
	    }
            else
              show_response_error("saving option name", xport);
	  }  // otherwise cancelled edit
        }
      }.bind(opt),
      onException: handle_exception
      });

}

function prodopt_add_value_ipe(opt, val) {
    new Ajax.InPlaceEditor("prodoptvalue"+val.id, edit_script,
      {
      cancelControl: "button",
      okText: "Save",
      cancelText: "Cancel",
      maxlength: 255,
      callback: function(f, v) {
        return "_=1&_t=prodopts&_csrfp="+ edit_value_csrf +"&id="+article_id+"&a_save_option_value=1&value_id="+this.id+"&value="+encodeURIComponent(v);
      }.bind(val),
      onComplete: function(xport) {
        var value_ele = $("prodoptvalue"+this.id);
        value_ele.innerHTML = "";
        var new_value;
        if (xport
            && xport.status == 200
            && xport.responseJSON
            && xport.responseJSON.success) {
          new_value = xport.responseJSON.value.value;
	  val.value = new_value;
          value_ele.appendChild(document.createTextNode(new_value));
        }
        else {
          // restore the original name
          new_value = val.value;
          value_ele.appendChild(document.createTextNode(new_value));
          if (xport) {
            if (xport.responseJSON && xport.responseJSON.errors.value) {
              alert("Error saving option value: "
	            + xport.responseJSON.errors.value);
	    }
            else
              show_response_error("saving option value", xport);
	  }  // otherwise cancelled edit
        }
      }.bind(val),
      onException: handle_exception
      });

}

function prodopt_add_value_hooks(opt, val) {
  if (user_can_edit_option) {
    prodopt_add_value_ipe(opt, val);
  }
}

function prodopt_add_option_hooks(opt) {
  var opt_ele_id = 'prodoptmenu' + opt.id;
  var opt_ele = $(opt_ele_id);
  var edit_ele_id = "editoption" + opt.id;
  var edit_ele = $(edit_ele_id);
  if (user_can_edit_option)
    prodopt_add_option_ipe(opt);
    if (user_can_edit_option) {
      fix_prodoptval_order_tools(opt);
      Sortable.create("vallist"+opt.id,
        {
	  tag: "div",
	  only: "valueentry",
          format: /^valentry(\d+)$/,
	  hoverclass: "valentryhover",
          onUpdate: function (parent) {
            var m = /^vallist(\d+)/.exec(parent.id);
            if (m) {
              reorder_prodoptvals_req("sortvalues"+m[1], m[1],
                Sortable.sequence(parent.id));
            }
          },
          onException: handle_exception
     });
    for (var i = 0; i < opt.values.length; ++i) {
      prodopt_add_value_hooks(opt, opt.values[i]);
    }
  }
}

function prodopts_start() {
  menu = $('prodoptmenu');
  var sortopts = $('sortoptions');
  if (sortopts) {
    sortopts.href="javascript:sort_prodopts()";
  }
  var reverseopts = $('reverseoptions');
  if (reverseopts) {
    reverseopts.href="javascript:reverse_prodopts()";
  }
  busy_img = $('busy_img');
  if (user_can_move_option) {
    Sortable.create("productoptions",
      {
        tag: "div",
        only: "prodopt",
        format: /^prodopt(\d+)$/,
        handle: "prodoptmenu",
        onUpdate: function () {
          reorder_prodopts_req("sortoptions",
              Sortable.sequence("productoptions"));
        },
            onException: handle_exception
      });
  }
  for (var opt_index = 0; opt_index < prodopts.length; ++opt_index) {
    var opt = prodopts[opt_index];
    prodopts_by_id[opt.id] = opt;
    try {
      prodopt_add_option_hooks(opt);
    }
    catch (e) {
      alert("init:"+e);
    }
  }
  fix_prodopt_order_tools();
}

Event.observe(document, "dom:loaded",
  function() {
    var add_option_form = $('addoptionform');
    var add_option_button = $('addoptionbutton');
    if (add_option_form && add_option_button && prodopts.length != 0
        && !show_add_form) {
      add_option_form.style.display='none';
      add_option_button.style.display = 'block';
    }
  });

Event.observe(document, "dom:loaded", prodopts_start);

