var BSEMenuUI = Class.create
(BSEUIBase,
{
  order: function() { return "a"; },
  display: function(ui, div, args) {
    div.innerHTML = this.content.menu;
  },
  needed_content: function(ui, args) {
    return { menu: "/admin/ui/menu.html" };
  },
  menu_text: function() { return "Main Menu"; }
});

ui.register("menu", new BSEMenuUI());