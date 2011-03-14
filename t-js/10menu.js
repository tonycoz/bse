document.observe("dom:loaded", function() {
  plan(7);

  ok(BSEMenu, "have a BSEMenu class");
  ok(BSEMenu.Item, "have a BSEMenu.Item class");
  ok(BSEMenu.SubMenu, "have a BSEMenu.SubMenu class");

  var clicked = function(item) { diag("Item " + item.text + " clicked") };

  var bar = $("nav");
  {
    var m1 = new BSEMenu({
      title: "Test 1",
      current: true,
      items: [
	{
	  text: "Item A",
	  separator: true,
	  onClick: clicked
	},
	{
	  text: "Item B",
	  onClick: clicked
	}
      ]
    });
    ok(m1, "made a menu");
    bar.appendChild(m1.element());
  }
  {
    var itemfb = {
      text: "Item F b",
      check: true,
      checked: true
    };
    itemfb.onClick = function() {
      var check = !this.object.checked();
      this.object.setChecked(check);
      diag("Item F b clicked, now " + (check ? "" : "not ") + "checked");
    }.bind(itemfb);
    var items = [
	{
	  text: "Item E",
	  separate: true,
	  onClick: clicked
	},
	{
	  text: "Item F",
	  submenu: {
	    items: [
	      {
		text: "Item F a",
		disabled: true,
		onClick: function() { diag("item F a shouldn't be clickable") }
	      },
	      itemfb
	    ]
	  }
	}
    ];
    var m2 = new BSEMenu({
      title: "Test 2",
      items: items
    });
    bar.appendChild(m2.element());
    ok(m2, "made second menu, with submenu");
  }
  {
    var itemM = {
      text: "item M",
      onClick: clicked
    };
    var itemN = {
      text: "item N",
      onClick: clicked
    };
    var m3 = new BSEMenu({
      title: "Test 3",
      items: [
	itemM,
	itemN
      ]
    });
    ok(m3, "made third menu");
    bar.appendChild(m3.element());
    m3.setText("Test 3 modified");
    itemN.object.setText("Item N modified");
    itemN.object.setSubmenu(new BSEMenu.SubMenu({
      items: [
	{
	  text: "item Na added",
	  onClick: clicked
	},
	{
	  text: "item Nb added",
	  onClick: clicked
	},
	{
	  text: "item Nc added",
	  onClick: clicked
	},
	{
	  text: "item Nd added",
	  onClick: clicked
	},
	{
	  text: "item Ne added",
	  onClick: clicked
	}
      ]
    }));
  }
  {
    var subT = new Element("ul");
    var li1 = new Element("li");
    li1.appendChild(new Element("input", { type: "text" }));
    subT.appendChild(li1);
    var li2 = new Element("li");
    var a2 = new Element("a", { href: "#" });
    a2.update("Foo");
    li2.appendChild(a2);
    subT.appendChild(li2);
    
    var itemT = {
      text: "Articles",
      submenu: {
	element: subT
      }
    };
    var m4 = new BSEMenu({
      title: "Articles",
      items: [
	{
	  text: "New article",
	  onClick: clicked
	},
	itemT
      ]
    });
    bar.appendChild(m4.element());
    ok(m4, "made m4");
  }
  tests_done();
});

