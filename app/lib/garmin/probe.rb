class Garmin::Probe
  Candidate = Data.define(:metric, :template, :span, :signal, :depth, :bisect)

  BUDGETS = {all: 60, documented: 30}
  COMPARED = {
    resting_hr: %w[heartRate restingValue],
    stress_avg: %w[stress avgLevel],
    body_battery_high: %w[bodyBattery maxValue],
    body_battery_low: %w[bodyBattery minValue]
  }
  COMPARE_DAYS = 7
  MAX_BISECT_STEPS = 8
  ZONE_PATHS = %w[/biometric-service/heartRateZones /biometric-service/heartRateZones/v2 /biometric-service/heartRateZones/all]
  SOCIAL_PATH = "/userprofile-service/socialProfile"
  LEGACY = [
    {metric: "resting_hr", template: "/usersummary-service/usersummary/daily?calendarDate={date}", signal: %w[restingHeartRate]},
    {metric: "resting_hr", template: "/wellness-service/wellness/dailyHeartRate?date={date}", signal: %w[restingHeartRate]},
    {metric: "resting_hr", template: "/usersummary-service/usersummary/daily/{displayName}?calendarDate={date}", signal: %w[restingHeartRate]},
    {metric: "stress", template: "/usersummary-service/stats/stress/daily/{start}/{end}", signal: %w[* values]},
    {metric: "stress", template: "/wellness-service/wellness/dailyStress/{date}"},
    {metric: "body_battery", template: "/wellness-service/wellness/bodyBattery/reports/daily?startDate={start}&endDate={end}", signal: %w[* startTimestampGMT]},
    {metric: "sleep", template: "/sleep-service/sleep/dailySleepData?date={date}", signal: %w[dailySleepDTO sleepTimeSeconds]},
    {metric: "sleep", template: "/wellness-service/wellness/dailySleepData?date={date}", signal: %w[dailySleepDTO sleepTimeSeconds]},
    {metric: "sleep", template: "/wellness-service/wellness/dailySleepData/{displayName}?date={date}", signal: %w[dailySleepDTO sleepTimeSeconds]},
    {metric: "sleep", template: "/sleep-service/stats/sleep/daily/{start}/{end}"},
    {metric: "hrv", template: "/hrv-service/hrv/{date}", signal: %w[hrvSummary lastNightAvg]},
    {metric: "hrv", template: "/hrv-service/hrv/daily/{start}/{end}", signal: %w[hrvSummaries * lastNightAvg]},
    {metric: "weight", template: "/weight-service/weight/range/{start}/{end}?includeAll=true", span: 29, signal: %w[dailyWeightSummaries]},
    {metric: "weight", template: "/weight-service/weight/dateRange?startDate={start}&endDate={end}", span: 29},
    {metric: "training_readiness", template: "/metrics-service/metrics/trainingreadiness/{date}"},
    {metric: "training_status", template: "/metrics-service/metrics/trainingstatus/daily/{date}"},
    {metric: "training_status", template: "/metrics-service/metrics/trainingstatus/aggregated/{date}"},
    {metric: "vo2max", template: "/metrics-service/metrics/maxmet/daily/{start}/{end}"},
    {metric: "vo2max", template: "/metrics-service/metrics/maxmet/latest/{date}"}
  ].map { Candidate.new(span: 6, signal: nil, depth: 1, bisect: true, **it) }
  DOCUMENTED = [
    {metric: "sleep", template: "/sleep-service/sleep/dailySleep?date={date}", depth: 3},
    {metric: "sleep", template: "/sleep-service/sleep/dailySleepSummariesByDate?startDate={start}&endDate={end}", span: 30, depth: 3},
    {metric: "daily_v2", template: "/usersummary-service/v2/dailysummaries?startDate={start}&endDate={end}"},
    {metric: "activity_detail", template: "/activity-service/activity/{activityId}", depth: 2, bisect: false}
  ].map { Candidate.new(**{span: 6, signal: nil, depth: 1, bisect: true}.merge(it)) }
  ID_KEY = /\Aid\z|Id\z|ID\z|PK\z|Pk\z/
  MAX_KEYS = 120

  def initialize(client:, first_run_on:, path:, activity_id: nil, scope: :documented, today: Date.current)
    @client = client
    @activity_id = activity_id
    @scope = scope
    @today = today
    @candidates = (scope == :all) ? LEGACY + DOCUMENTED : DOCUMENTED
    @first_run_on = first_run_on
    @yesterday = today - 1
    @year_ago = today - 365
    @path = path
    @results = {}
  end

  def run
    open_output

    zones if @scope == :all
    survey_candidates
    earliest = metrics.index_with { bisect(it) }
    compare if @scope == :documented
    summarize(earliest)
  ensure
    @file&.close
  end

  private
  def open_output
    directory = File.dirname(@path)
    created = !Dir.exist?(directory)
    FileUtils.mkdir_p(directory, mode: 0o700)
    FileUtils.chmod(0o700, directory) if created
    @file = File.open(@path, "w", 0o600)
    @file.chmod(0o600)
  end

  def zones
    social = fetch(SOCIAL_PATH)
    settings = fetch(Garmin::Client::SETTINGS_PATH)
    @display_name = [social, settings].filter_map { it[:body]["displayName"] if it[:body].is_a?(Hash) }.first
    emit("displayName: #{@display_name ? "found" : "missing"}")
    @zones = ZONE_PATHS.index_with { fetch(it) }
  end

  def survey_candidates
    @candidates.each { @results[it] = survey(it) }
  end

  def survey(candidate)
    return {once: attempt(candidate, nil, "once")} unless dated?(candidate)

    found = {yesterday: attempt(candidate, @yesterday, "yesterday")}
    found[:year_ago] = attempt(candidate, @year_ago, "year ago") unless found[:yesterday].nil?
    found[:first_run] = attempt(candidate, @first_run_on, "first run") if found[:year_ago]
    found
  end

  def dated?(candidate)
    candidate.template.match?(/\{(date|start)\}/)
  end

  def attempt(candidate, date, label)
    if candidate.template.include?("{displayName}") && @display_name.nil?
      emit("SKIP #{candidate.template} (no displayName)")
      return
    end

    if candidate.template.include?("{activityId}") && @activity_id.nil?
      emit("SKIP #{candidate.template} (no run id)")
      return
    end

    subs = {activityId: @activity_id, displayName: CGI.escapeURIComponent(@display_name.to_s)}
    subs.merge!(date:, start: date - candidate.span, end: date) if date
    result = fetch(candidate.template, label:, subs:, signal: candidate.signal, depth: candidate.depth)
    result[:data] if result[:ok]
  end

  def metrics
    @candidates.select(&:bisect).map(&:metric).uniq
  end

  def bisect(metric)
    best = best_candidate(metric)
    return unless best

    candidate, dates = best
    hi = dates.first
    lo = dates_before(hi)
    steps = [(BUDGETS[@scope] - reserved - @client.request_count) / pending_metrics(metric), MAX_BISECT_STEPS].min

    while steps > 0 && lo && (hi - lo) > candidate.span
      steps -= 1
      mid = lo + (hi - lo).to_i / 2
      outcome = attempt(candidate, mid, "bisect")
      break if outcome.nil?

      if outcome
        hi = mid
      else
        lo = mid
      end
    end

    {candidate:, date: hi, within: lo && (hi - lo).to_i}
  end

  def best_candidate(metric)
    @candidates.select { it.metric == metric }.filter_map do |candidate|
      dates = dates_with_data(@results[candidate])
      [candidate, dates] if dates.any?
    end.min_by { |_, dates| dates.first }
  end

  def dates_with_data(found)
    dates = {first_run: @first_run_on, year_ago: @year_ago, yesterday: @yesterday}
    dates.select { |key, _| found[key] }.values
  end

  def dates_before(date)
    {@year_ago => @first_run_on, @yesterday => @year_ago}[date]
  end

  def reserved
    (@scope == :documented) ? 1 : 0
  end

  def pending_metrics(metric)
    [metrics.drop_while { it != metric }.count { best_candidate(it) }, 1].max
  end

  def fetch(template, label: nil, subs: {}, signal: nil, depth: 1)
    path = subs.reduce(template) { |text, (key, value)| text.gsub("{#{key}}", value.to_s) }
    response = @client.probe(path)
    body = parse(response.body)
    ok = response.is_a?(Net::HTTPSuccess)
    data = ok && signal?(body, signal)

    emit("GET #{template}#{" [#{label}]" if label} -> #{response.code} #{response["Content-Type"]} data=#{data ? "yes" : "no"}")
    emit("  #{describe(body, response.body, depth)}") if ok
    {ok:, body:, data:}
  rescue *Garmin::Client::TRANSIENT_ERRORS => error
    emit("GET #{template}#{" [#{label}]" if label} -> #{error.class.name}")
    {ok: false, body: nil, data: false}
  end

  def parse(text)
    JSON.parse(text.to_s)
  rescue JSON::ParserError
    nil
  end

  def signal?(body, path)
    if path.nil?
      data?(body)
    elsif path.empty?
      body.is_a?(Hash) || body.is_a?(Array) ? data?(body) : !body.nil?
    elsif path.first == "*"
      body.is_a?(Array) && body.any? { signal?(it, path.drop(1)) }
    else
      body.is_a?(Hash) && signal?(body[path.first], path.drop(1))
    end
  end

  def data?(node)
    case node
    when Hash then node.any? { |key, value| !ID_KEY.match?(key) && data?(value) }
    when Array then node.any? { data?(it) }
    when Numeric then node != 0
    else false
    end
  end

  def describe(body, text, depth)
    case body
    when Hash then "keys: #{shape(body, depth)}"
    when Array then "array[#{body.size}]#{nested(body, depth)}"
    when nil then text.to_s.empty? ? "empty body" : "not JSON (#{text.bytesize} bytes)"
    else "scalar: #{type(body)}"
    end
  end

  def shape(hash, depth)
    entries = hash.first(MAX_KEYS).map { |key, value| "#{name(key)}:#{type(value)}#{nested(value, depth)}" }
    entries << "…" if hash.size > MAX_KEYS
    entries.join(", ")
  end

  def nested(value, depth = 1)
    inner = value.is_a?(Array) ? value.find { it.is_a?(Hash) } : value
    return "" unless inner.is_a?(Hash)

    entries = inner.first(MAX_KEYS).map { |key, child| "#{name(key)}:#{type(child)}#{nested(child, depth - 1) if depth > 1}" }
    entries << "…" if inner.size > MAX_KEYS
    "{#{entries.join(", ")}}"
  end

  def type(value)
    case value
    when Hash then "object"
    when Array then "array[#{value.size}]"
    when String then "string"
    when Numeric then "number"
    when true, false then "boolean"
    else "null"
    end
  end

  def name(key)
    key.to_s.sub(/\A\d{4,}\z/, "<id>").gsub(/\d{4}-\d{2}-\d{2}\S*/, "<date>")
  end

  def compare
    days = WellnessDay.where(date: (@today - COMPARE_DAYS)...@today).where.not(resting_hr: nil).order(:date).to_a
    return if days.empty?

    from, to = days.map(&:date).minmax
    candidate = DOCUMENTED.find { it.metric == "daily_v2" }
    result = fetch(candidate.template, label: "compare", subs: {start: from, end: to})
    entries = result[:body].is_a?(Hash) ? Array(result[:body]["data"]) : []

    emit("")
    emit("COMPARE v2 against stored daily summary (#{days.size} days, counts only)")
    COMPARED.each do |column, path|
      pairs = days.filter_map { |day| [day[column], entries.find { it["calendarDate"] == day.date.to_s }&.dig(*path)] }
      both = pairs.select { |stored, v2| stored && v2 }
      emit("#{column}: #{both.count { |stored, v2| stored == v2 }} of #{both.size} match, #{days.size - both.size} missing on one side")
    end
    emit("v2 key paths mentioning seven, wake or sleep: #{key_paths(entries.first).grep(/seven|wake|sleep/i).presence&.join(", ") || "none"}")
  end

  def key_paths(node, prefix = nil)
    return [] unless node.is_a?(Hash)

    node.flat_map { |key, value| ["#{prefix}#{name(key)}"] + key_paths(value, "#{prefix}#{name(key)}.") }
  end

  def summarize(earliest)
    emit("")
    emit("SUMMARY (#{@client.request_count} requests)")
    if @zones
      zone_path = ZONE_PATHS.find { @zones[it][:data] }
      emit("hr_zones: #{zone_path ? "GET #{zone_path}" : "not available"}")
    end

    earliest.each do |metric, found|
      if found
        precision = found[:within] ? "within #{found[:within]} days" : "first run date, may be earlier"
        emit("#{metric}: GET #{found[:candidate].template}, earliest data #{found[:date]} (#{precision})")
      else
        emit("#{metric}: not available")
      end
    end
  end

  def emit(line)
    $stdout.puts(line)
    @file.puts(line)
  end
end
