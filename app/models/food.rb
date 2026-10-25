class Food
  Item = Data.define(:singular, :plural, :kcal)

  Serving = Data.define(:count, :item) do
    def to_s
      "#{count} #{(count == 1) ? item.singular : item.plural}"
    end
  end

  ITEMS = [
    Item.new("banana", "bananas", 105),
    Item.new("croissant", "croissants", 230),
    Item.new("doughnut", "doughnuts", 260),
    Item.new("cheeseburger", "cheeseburgers", 300),
    Item.new("kremšnita", "kremšnitas", 450),
    Item.new("pizza", "pizzas", 1600)
  ].freeze

  MAX_COUNT = 12

  def self.for(calories)
    if calories&.positive?
      servings = ITEMS.flat_map { |item| (1..MAX_COUNT).map { Serving.new(it, item) } }
      servings.min_by { [(it.item.kcal * it.count - calories).abs, it.count] }
    end
  end
end
