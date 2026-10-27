class Gear < ApplicationRecord
  STALE_AFTER = 1.week
  RECENT_DAYS = 365
  MONTH_SQL = Arel.sql("strftime('%Y-%m', local_started_at)")

  Usage = Data.define(:gear, :runs, :km, :seconds, :recent_km, :last_used)

  validates :strava_id, presence: true

  def self.usage
    since = recent_since
    rows = Activity.where.not(strava_gear_id: nil).group(:strava_gear_id).pluck(:strava_gear_id, *aggregates(since))
    gears = where(strava_id: rows.map(&:first)).index_by(&:strava_id)

    rows.map { |id, *values| usage_for(gears[id] || new(strava_id: id), *values) }.sort_by { [-it.runs, -it.km] }
  end

  def self.unset_usage
    runs, *values = Activity.gear_unset.pick(*aggregates(recent_since))

    usage_for(nil, runs, *values) if runs.to_i.positive?
  end

  def self.monthly(usage)
    sums = Activity.where.not(strava_gear_id: nil).group(MONTH_SQL, :strava_gear_id).sum(:distance_m)

    if sums.empty?
      {months: [], gears: []}
    else
      first, last = sums.keys.map(&:first).minmax.map { Date.strptime(it, "%Y-%m") }
      months = (first..last).select { it.day == 1 }
      gears = usage.map { |row| {id: row.gear.strava_id, name: row.gear.display_name, retired: row.gear.retired, km: months.map { (sums[[it.strftime("%Y-%m"), row.gear.strava_id]].to_f / 1000).round(2) }} }

      {months: months.map(&:iso8601), gears:}
    end
  end

  def self.recent_since
    latest = Activity.maximum(:local_started_at)

    latest.to_date - (RECENT_DAYS - 1) if latest
  end

  def self.aggregates(since)
    recent = sanitize_sql_array(["SUM(CASE WHEN local_started_at >= ? THEN distance_m ELSE 0 END)", since])

    [Arel.sql("COUNT(*)"), Arel.sql("SUM(distance_m)"), Arel.sql("SUM(timer_s)"), Arel.sql(recent), Arel.sql("MAX(local_started_at)")]
  end

  def self.usage_for(gear, runs, meters, seconds, recent_meters, last_used)
    Usage.new(gear:, runs:, km: meters.to_f / 1000, seconds: seconds.to_f, recent_km: recent_meters.to_f / 1000, last_used: Time.zone.parse(last_used.to_s))
  end

  def self.sync(ids, client:, force: false)
    ids.each do |id|
      gear = find_by(strava_id: id)
      fetch(id, client:) if force || gear.nil? || gear.stale?
    end
  end

  def self.fetch(id, client:)
    payload = client.gear(id)
    gear = create_or_find_by!(strava_id: id)

    if payload
      gear.update!(name: payload["name"], brand_name: payload["brand_name"], model: payload["model_name"], retired: payload["retired"] == true, summary: payload, synced_at: Time.current)
    else
      gear.update!(synced_at: Time.current)
    end
  end

  def display_name
    name.presence || strava_id
  end

  def description
    [brand_name, model].compact_blank.join(" ")
  end

  def dead?
    synced_at.present? && summary.nil?
  end

  def stale?
    synced_at.nil? || synced_at < STALE_AFTER.ago
  end
end
