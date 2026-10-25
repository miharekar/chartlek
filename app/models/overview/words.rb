class Overview::Words
  ONES = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen].freeze
  TENS = %w[zero ten twenty thirty forty fifty sixty seventy eighty ninety].freeze
  SCALES = [[1_000_000_000, "billion"], [1_000_000, "million"], [1_000, "thousand"]].freeze

  def self.for(number)
    if number < 20
      ONES[number]
    elsif number < 100
      join(TENS[number / 10], number % 10)
    elsif number < 1000
      join("#{ONES[number / 100]} hundred", number % 100)
    else
      value, name = SCALES.find { number >= it.first }
      join("#{self.for(number / value)} #{name}", number % value)
    end
  end

  def self.join(head, rest)
    if rest.zero?
      head
    else
      "#{head} #{self.for(rest)}"
    end
  end
  private_class_method :join
end
