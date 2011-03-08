function _test_out(text, cls) {
  var test_ele = document.getElementById('tests');
  if (test_ele) {
    var div_tag = document.createElement("div");
    if (cls != null)
      div_tag.className = cls;
    var t = document.createTextNode(text);
    div_tag.appendChild(t);
    test_ele.appendChild(div_tag);
    //var open_tag;
    //if (cls == null)
      //open_tag = "<div>";
    //else
      //open_tag = '<div class="' + cls + '">';
    //test_ele.innerHTML = test_ele.innerHTML + open_tag + escape_html(text) + "</div>";
  }
}

var test_ok = 0;
var test_fails = 0;
var test_skips = 0;
var test_num = 1;
var test_count;

function plan(count) {
  test_count = count;
  _test_out("1.." + count, "plan");
}

function ok(test, comment) {
  if (test) {
    ++test_ok;
    _test_out("ok " + test_num + " # " + comment, "ok");
  }
  else {
    _test_out("not ok " + test_num + " # " + comment, "fail");
    ++test_fails;
  }
  ++test_num;
  return test;
}

function skip(text, count) {
  if (count == null)
    count = 1;
  for (var i = 0; i < 1; ++i) {
    _test_out("ok " + test_num + " SKIP text", "skip");
    ++test_skips;
    ++test_num;
  }
}

function is(left, right, comment) {
  var test_ok = ok(left == right, comment);
  if (!test_ok) {
    _test_out("# should match", "fail");
    _test_out("# left :'"+encodeURI(left)+"'", "fail");
    _test_out("# right:'"+encodeURI(right)+"'", "fail");
  }
  return test_ok;
}

function isnt(left, right, comment) {
  var test_ok = ok(left != right, comment);
  if (!test_ok) {
    _test_out("# shouldn't match", "fail");
    _test_out("# left :"+encodeURI(left), "fail");
    _test_out("# right:"+encodeURI(right), "fail");
  }
  return test_ok;
}

function like(value, re, comment) {
  var test_ok = ok(value != null && value.match(re), comment);
  if (!test_ok) {
    _test_out("# should match", "fail");
    _test_out("# value:"+value, "fail");
    _test_out("# regexp:"+re, "fail");
  }
  return test_ok;
}

function diag(text) {
  _test_out("# " + text, "diag");
}

function tests_done() {
  var cls = "ok";
  var top_class = "passed";
  if (test_count != null) {
    if (test_count != test_num-1) {
      _test_out("Expected "+test_count+" tests but saw "+(test_num-1), "fail");
      cls = "fail";
      top_class = "failed";
    }
  }
  if (test_fails != 0) {
    cls = "fail";
    top_class = "failed";
  }
  _test_out("Summary: "+(test_num-1)+" tests, "+test_ok+" Ok, "+test_fails+" failures " + test_skips + " skips", cls);
  var test_ele = document.getElementById('tests');
  test_ele.className = top_class;
}

function ok_noexception(f, text) {
  var result;
  try {
    result = f();
  }
  catch (e) {
    ok(false, text);
    diag(e.message);
    return false;
  }

  ok(true, text);
  return result;
}

function ok_exception(f, text, match) {
  var result;
  try {
    f();
  }
  catch (e) {
    ok(true, text);
    diag(e.message);
    return e.message;
  }

  ok(false, text);
  return false;
}
