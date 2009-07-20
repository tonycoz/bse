var prodopts_by_id = new Object;
var menu;

function reorder_option_values(id, order) {
  var parent = $("vallist"+id);
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

  // TODO: reorder the values in prodopts
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
      if (json.success) {
        reorder_options(json.order);
      }
      else {
        alert("Error ordering: " + json.error);
      }
    },
    onFailure: function() {
      alert("Error contacting server");
      set_not_busy("prodoptmove"+id);
    }
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
      var move_down = document.createElement("a");
      move_down.href="javascript:prodopt_move_down("+opt.id+")";
      var down_img = document.createElement("img");
      down_img.src = "/images/admin/move_down.gif";
      move_down.appendChild(down_img);
      move_ele.appendChild(move_down);
    }
    else {
      var empty = document.createElement('img');
      empty.src = "/images/trans_pixel.gif";
      move_ele.appendChild(empty);
    }
    if (i != 0) {
      var move_up = document.createElement("a");
      move_up.href="javascript:prodopt_move_up("+opt.id+")";
      var up_img = document.createElement("img");
      up_img.src = "/images/admin/move_up.gif";
      move_up.appendChild(up_img);
      move_ele.appendChild(move_up);
    }
    else {
      var empty = document.createElement('img');
      empty.src = "/images/trans_pixel.gif";
      move_ele.appendChild(empty);
    }
  }
}

var busy_img = $('busy_img');

function set_busy(id) {
  if (busy_img)
    busy_img.style.display = 'inline';
}
function set_not_busy(id) {
  if (busy_img)
    busy_img.style.display = 'none';
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
    }
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
      if (json.success) {
        reorder_options(json.order);
      }
      else {
        alert("Error ordering: " + json.error);
      }
    },
    onFailure: function() {
      alert("Error contacting server");
      set_not_busy(ele_id);
    }
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

  for (var i = 0; i < prodopts.length; ++i) {
    var opt = prodopts[i];
    prodopts_by_id[opt.id] = opt;
//    var opt_ele_id = 'prodoptmenu' + opt.id;
//    var opt_ele = $(opt_ele_id);
//    opt_ele.appendChild(document.createTextNode(" "));
//    var sort_a = document.createElement("a");
//    sort_a.href = "javascript:sort_prodopt_values('" + opt.id + "')";
//    sort_a.title = "Sort values alphabetically";
//    sort_a.appendChild(document.createTextNode("Sort"));
//    opt_ele.appendChild(sort_a);
  }
  fix_prodopt_order_tools();
}
