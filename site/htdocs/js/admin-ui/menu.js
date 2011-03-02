var BSEMenuUI = Class.create
(BSEUIBase,
{
  order: function() { return "a"; },
  start: function(ui, div, args) {
    div.innerHTML = "There will be a menu here";
  },
    display: function(ui, div) {
    },
  needed_content: function(ui, args) {
    return { menu: "/admin/ui/menu.html" };
  },
  menu_text: function() { return "Main Menu"; }
});

ui.register("menu", new BSEMenuUI());