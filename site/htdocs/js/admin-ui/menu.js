var BSEMenuUI = Class.create
(BSEUIBase,
{
  start: function(ui, div, args) {
    div.innerHTML = "There will be a menu here";
  },
    display: function(ui, div) {
    },
  needed_content: function(ui, args) {
    return { menu: "/admin/ui/menu.html" };
  }
});

ui.menu_item({
  name: "menu",
  object: new BSEMenuUI,
  text: "Main Menu",
  order: "a"
});