class Notables::Moon
  REFERENCE_NEW_MOON = Time.utc(2000, 1, 6, 18, 14)
  SYNODIC_DAYS = 29.530588853
  MARGIN_DAYS = 1

  def self.phase(time)
    age = ((time - REFERENCE_NEW_MOON) / 1.day) % SYNODIC_DAYS

    if age <= MARGIN_DAYS || age >= SYNODIC_DAYS - MARGIN_DAYS
      :new
    elsif (age - SYNODIC_DAYS / 2).abs <= MARGIN_DAYS
      :full
    end
  end
end
