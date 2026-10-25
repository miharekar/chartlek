require "test_helper"
require_relative "../../lib/garmin/api_stubs"

class Activity::GarminSyncTest < ActiveSupport::TestCase
  include GarminApiStubs
  include ActionCable::TestHelper

  setup do
    stub_token
    stub_settings
  end

  def zip(name, content)
    Zip::OutputStream.write_buffer { |zip| zip.put_next_entry(name) && zip.write(content) }.string
  end

  def fit_zip
    zip("1_ACTIVITY.fit", file_fixture("tracks/run.fit").binread)
  end

  def fit_summary(**overrides)
    garmin_summary({startTimeGMT: "2024-03-05 06:30:00", startTimeLocal: "2024-03-05 07:30:00", distance: 1560.0, duration: 390.0, elapsedDuration: 490.0}.merge(overrides))
  end

  def garmin_run(**attributes)
    create(:activity, started_at: Time.utc(2024, 3, 5, 6, 30), distance_m: 1560.0, timer_s: 390.0, elapsed_s: 490.0, **attributes)
  end

  def attach_fit(activity)
    activity.original.attach(io: StringIO.new(fit_zip), filename: "#{activity.external_id}.zip", content_type: "application/zip")
  end

  test "sync_later enqueues the job" do
    assert_enqueued_with(job: Activity::SyncJob) { Activity.sync_later }
  end

  test "job runs a sync" do
    stub_page(0, [garmin_summary])

    perform_enqueued_jobs { Activity.sync_later }

    assert_equal 1, Activity.count
  end

  test "maps summary fields" do
    stub_page(0, [garmin_summary(eventType: {typeKey: "race"})])

    Activity.sync_now

    activity = Activity.sole
    assert_equal "garmin", activity.source
    assert_equal "9000001", activity.external_id
    assert_equal Time.utc(2024, 3, 5, 6, 30, 15), activity.started_at
    assert_equal "Test Town Running", activity.name
    assert_equal "running", activity.activity_type
    assert_not activity.indoor
    assert activity.race
    assert_equal 10234.5, activity.distance_m
    assert_equal 3001.4, activity.timer_s
    assert_equal 2990.2, activity.moving_s
    assert_equal 3100.9, activity.elapsed_s
    assert_equal 85.0, activity.elevation_gain_m
    assert_equal 80.5, activity.elevation_loss_m
    assert_equal 151, activity.avg_hr
    assert_equal 177, activity.max_hr
    assert_equal 170.5, activity.avg_cadence
    assert_equal 190.0, activity.max_cadence
    assert_equal 702, activity.calories
    assert_equal 52.0, activity.vo2max
    assert_equal 10.0, activity.start_lat
    assert_equal 20.0, activity.start_lng
    assert_equal "Test Town", activity.location_name
    assert_equal 9000001, activity.summary["activityId"]
  end

  test "stores local time without shifting it" do
    stub_page(0, [garmin_summary(startTimeLocal: "2024-07-01 23:45:00", startTimeGMT: "2024-07-01 13:45:00")])

    Activity.sync_now

    assert_equal Time.utc(2024, 7, 1, 23, 45), Activity.sole.local_started_at
    assert_equal Time.utc(2024, 7, 1, 13, 45), Activity.sole.started_at
  end

  test "flags indoor subtypes" do
    stub_page(0, [garmin_summary(activityId: 1, activityType: {typeKey: "treadmill_running"}), garmin_summary(activityId: 2, activityType: {typeKey: "trail_running"})])

    Activity.sync_now

    assert Activity.find_by(external_id: "1").indoor
    assert_not Activity.find_by(external_id: "2").indoor
  end

  test "skips non-running types and tiny distances" do
    stub_page(0, [garmin_summary(activityId: 1), garmin_summary(activityId: 2, activityType: {typeKey: "cycling"}), garmin_summary(activityId: 3, distance: 99.0)])

    Activity.sync_now

    assert_equal %w[1], Activity.pluck(:external_id)
  end

  test "updates existing activities instead of duplicating" do
    create(:activity, external_id: "9000001", name: "Old")
    stub_page(0, [garmin_summary])

    Activity.sync_now

    assert_equal "Test Town Running", Activity.sole.name
  end

  test "stores profile settings and sync state" do
    stub_page(0, [])
    profile = Profile.instance

    Activity.sync_now

    profile.reload
    assert_equal "metric", profile.settings["measurementSystem"]
    assert profile.synced_at
    assert_nil profile.sync_started_at
    assert_nil profile.sync_error
  end

  test "pages until a short page" do
    stub_page(0, garmin_summaries(100))
    second = stub_page(100, garmin_summaries(40, first_id: 9200000))

    Activity.sync_now

    assert_requested second
    assert_equal 140, Activity.count
  end

  test "incremental sync stops at a full page of known activities" do
    known = garmin_summaries(100)
    known.each { create(:activity, external_id: it["activityId"].to_s) }
    first = stub_page(0, known)
    second = stub_page(100, garmin_summaries(100, first_id: 9200000))

    Activity.sync_now

    assert_requested first
    assert_not_requested second
  end

  test "incremental sync keeps paging while a page has unknown activities" do
    page = garmin_summaries(100)
    page.first(99).each { create(:activity, external_id: it["activityId"].to_s) }
    stub_page(0, page)
    second = stub_page(100, [])

    Activity.sync_now

    assert_requested second
  end

  test "ineligible activities count as known for the stop rule" do
    page = garmin_summaries(99) + [garmin_summary(activityId: 9300000, activityType: {typeKey: "cycling"})]
    page.first(99).each { create(:activity, external_id: it["activityId"].to_s) }
    first = stub_page(0, page)
    second = stub_page(100, garmin_summaries(100, first_id: 9200000))

    Activity.sync_now

    assert_requested first
    assert_not_requested second
  end

  test "full resync pages through known activities and deletes unseen ones after a complete pass" do
    page = garmin_summaries(100)
    page.each { create(:activity, external_id: it["activityId"].to_s) }
    create(:activity, external_id: "gone")
    create(:activity, source: "strava", external_id: "gone")
    stub_page(0, page)
    second = stub_page(100, [])

    Activity.sync_now(full: true)

    assert_requested second
    assert_equal 100, Activity.where(source: "garmin").count
    assert_not Activity.exists?(source: "garmin", external_id: "gone")
    assert Activity.exists?(source: "strava", external_id: "gone")
  end

  test "full resync deletes runs that became ineligible" do
    create(:activity, external_id: "9000001")
    stub_page(0, [garmin_summary(distance: 50.0), garmin_summary(activityId: 9000002)])
    stub_page(100, [])

    Activity.sync_now(full: true)

    assert_equal %w[9000002], Activity.pluck(:external_id)
  end

  test "full resync deletes nothing when a page fails" do
    create(:activity, external_id: "gone")
    stub_page(0, garmin_summaries(100))
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("start" => "100")).to_return(status: 500)

    Activity.sync_now(full: true)

    assert Activity.exists?(external_id: "gone")
    assert_match(/Sync failed/, Profile.instance.sync_error)
  end

  test "full resync with an empty pass keeps the local cache" do
    create(:activity, external_id: "kept")
    stub_page(0, [])

    Activity.sync_now(full: true)

    assert Activity.exists?(external_id: "kept")
    assert_nil Profile.instance.sync_error
  end

  test "a sync after a recorded error pages through all history without deleting" do
    page = garmin_summaries(100)
    page.each { create(:activity, external_id: it["activityId"].to_s) }
    create(:activity, external_id: "local-only")
    Profile.instance.update!(sync_error: "Sync failed: boom")
    stub_page(0, page)
    stub_page(100, garmin_summaries(40, first_id: 9200000))

    Activity.sync_now

    assert_equal 141, Activity.count
    assert Activity.exists?(external_id: "local-only")
    assert_nil Profile.instance.sync_error
  end

  test "a sync after a stale running state pages through all history" do
    page = garmin_summaries(100)
    page.each { create(:activity, external_id: it["activityId"].to_s) }
    Profile.instance.update!(sync_started_at: 20.minutes.ago)
    stub_page(0, page)
    stub_page(100, garmin_summaries(40, first_id: 9200000))

    Activity.sync_now

    assert_equal 140, Activity.count
  end

  test "an interrupted backfill resumes on the next sync" do
    stub_page(0, garmin_summaries(100))
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("start" => "100")).to_return(status: 500)

    Activity.sync_now

    assert_equal 100, Activity.count
    assert_predicate Profile.instance.sync_error, :present?

    WebMock.reset!
    stub_token
    stub_settings
    stub_download_missing
    stub_page(0, garmin_summaries(100))
    stub_page(100, garmin_summaries(40, first_id: 9200000))

    Activity.sync_now

    assert_equal 140, Activity.count
  end

  test "a sync after a success still stops at known activities" do
    page = garmin_summaries(100)
    page.each { create(:activity, external_id: it["activityId"].to_s) }
    Profile.instance.update!(synced_at: 1.hour.ago)
    stub_page(0, page)
    second = stub_page(100, garmin_summaries(40, first_id: 9200000))

    Activity.sync_now

    assert_not_requested second
  end

  test "records an invalid key" do
    WebMock.reset!
    stub_token(status: 401)

    Activity.sync_now

    profile = Profile.instance
    assert profile.invalid_key?
    assert_nil profile.synced_at
    assert_nil profile.sync_started_at
  end

  test "records other failures and clears the error on the next success" do
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("start" => "0")).to_return(status: 500)

    Activity.sync_now

    assert_match(/Sync failed/, Profile.instance.sync_error)
    assert_nil Profile.instance.sync_started_at

    stub_page(0, [])
    Activity.sync_now

    assert_nil Profile.instance.sync_error
  end

  test "does not run two syncs at once" do
    Profile.instance.update!(sync_started_at: 1.minute.ago)

    Activity.sync_now

    assert_not_requested :post, /personal-api-key\/token/
  end

  test "takes over a stale sync" do
    Profile.instance.update!(sync_started_at: 20.minutes.ago)
    stub_page(0, [garmin_summary])

    Activity.sync_now

    assert_equal 1, Activity.count
  end

  test "a sync without changes only replaces the status" do
    stub_page(0, [garmin_summary])
    Activity.sync_now
    stub_page(0, [garmin_summary])

    streams = capture_broadcasts("garmin_sync") { Activity.sync_now }

    assert_equal 2, streams.size
    assert(streams.all? { it.include?(%(action="replace" target="sync_status")) })
  end

  test "a sync shows syncing before it finishes" do
    stub_page(0, [])

    streams = capture_broadcasts("garmin_sync") { Activity.sync_now }

    assert_includes streams.first, "Syncing…"
  end

  test "a sync with new runs broadcasts a page refresh" do
    stub_page(0, [garmin_summary])

    streams = capture_broadcasts("garmin_sync") { Activity.sync_now }

    assert(streams.any? { it.include?(%(action="refresh")) })
  end

  test "a sync that changes a run broadcasts a page refresh" do
    create(:activity, external_id: "9000001", name: "Old")
    stub_page(0, [garmin_summary])

    streams = capture_broadcasts("garmin_sync") { Activity.sync_now }

    assert(streams.any? { it.include?(%(action="refresh")) })
  end

  test "a full resync that deletes runs broadcasts a page refresh" do
    create(:activity, external_id: "gone")
    stub_page(0, [garmin_summary])
    Activity.sync_now
    stub_page(0, [garmin_summary])
    stub_page(100, [])

    streams = capture_broadcasts("garmin_sync") { Activity.sync_now(full: true) }

    assert(streams.any? { it.include?(%(action="refresh")) })
  end

  test "a new error broadcasts a page refresh" do
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("start" => "0")).to_return(status: 500)

    streams = capture_broadcasts("garmin_sync") { Activity.sync_now }

    assert(streams.any? { it.include?(%(action="refresh")) })
  end

  test "a repeated identical error only replaces the status" do
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("start" => "0")).to_return(status: 500)
    Activity.sync_now

    streams = capture_broadcasts("garmin_sync") { Activity.sync_now }

    assert(streams.none? { it.include?(%(action="refresh")) })
  end

  test "a cleared error broadcasts a page refresh" do
    Profile.instance.update!(sync_error: "Sync failed: boom")
    stub_page(0, [])

    streams = capture_broadcasts("garmin_sync") { Activity.sync_now }

    assert(streams.any? { it.include?(%(action="refresh")) })
  end

  test "full resync keeps paging past a short page and deletes nothing when a later page fails" do
    create(:activity, external_id: "older")
    stub_page(0, garmin_summaries(60))
    stub_request(:get, ACTIVITIES_URL).with(query: hash_including("start" => "100")).to_return(status: 500)

    Activity.sync_now(full: true)

    assert Activity.exists?(external_id: "older")
  end

  test "full resync keeps paging past a short page until an empty one" do
    create(:activity, external_id: "older")
    stub_page(0, garmin_summaries(60))
    stub_page(100, garmin_summaries(10, first_id: 9200000))
    last = stub_page(200, [])

    Activity.sync_now(full: true)

    assert_requested last
    assert_equal 70, Activity.count
  end

  test "reports progress per page" do
    stub_page(0, garmin_summaries(100))
    stub_page(100, garmin_summaries(1, first_id: 9200000))
    pages = []

    Activity.sync_now { pages << it }

    assert_equal [{start: 0, fetched: 100, synced: 100}, {start: 100, fetched: 1, synced: 1}], pages
  end

  test "download attaches and processes originals and tallies formats" do
    run = garmin_run
    stub_download(run.external_id, fit_zip)

    report = Activity.download_originals

    assert_equal({attached: 1, processed: 1, formats: {"fit" => 1}, failed: {}}, report)
    assert_equal "#{run.external_id}.zip", run.reload.original.filename.to_s
    assert_equal "application/zip", run.original.content_type
    assert run.track
  end

  test "download skips runs that already have an original" do
    run = garmin_run
    attach_fit(run)
    other = garmin_run(source: "strava")

    report = Activity.download_originals

    assert_equal 0, report[:attached]
    assert_not_requested :get, /download-service/
    assert_not other.reload.original.attached?
  end

  test "download reports a failed download and carries on" do
    broken = garmin_run(started_at: Time.utc(2024, 3, 4, 6, 30))
    run = garmin_run
    stub_download(run.external_id, fit_zip)

    report = Activity.download_originals

    assert_equal 1, report[:processed]
    assert_match(/Garmin::Client::Error/, report[:failed][broken.id])
    assert_not broken.reload.original.attached?
  end

  test "download keeps the attachment when parsing fails" do
    run = garmin_run
    stub_download(run.external_id, zip("1_ACTIVITY.fit", "not a fit file"))

    report = Activity.download_originals

    assert_equal 1, report[:attached]
    assert_equal 0, report[:processed]
    assert_predicate report[:failed][run.id], :present?
    assert run.reload.original.attached?
    assert_nil run.track
  end

  test "sync downloads and processes the original of a new run" do
    stub_page(0, [fit_summary])
    download = stub_download("9000001", fit_zip)

    Activity.sync_now

    assert_requested download, times: 1
    run = Activity.sole
    assert run.original.attached?
    assert run.track
  end

  test "sync reprocesses a run whose processing inputs changed" do
    run = garmin_run(external_id: "9000001", timer_s: 380.0, distance_m: 1500.0)
    attach_fit(run)
    run.process_original
    run.update!(splits: nil)
    stub_page(0, [fit_summary])

    Activity.sync_now

    assert_not_requested :get, /download-service/
    assert_predicate run.reload.splits, :present?
  end

  test "sync leaves a run alone when only unrelated fields changed" do
    run = garmin_run(external_id: "9000001", name: "Old")
    attach_fit(run)
    run.process_original
    run.update!(splits: nil)
    stub_page(0, [fit_summary])

    Activity.sync_now

    assert_equal "Test Town Running", run.reload.name
    assert_nil run.splits
  end

  test "sync downloads the missing original of an existing run" do
    run = garmin_run(external_id: "9000001")
    stub_page(0, [fit_summary])
    download = stub_download("9000001", fit_zip)

    Activity.sync_now

    assert_requested download, times: 1
    assert run.reload.original.attached?
    assert run.track
  end

  test "a later sync retries a failed download" do
    stub_page(0, [fit_summary])
    stub_download_missing
    Activity.sync_now
    assert_not Activity.sole.original.attached?

    WebMock.reset!
    stub_token
    stub_settings
    stub_page(0, [fit_summary])
    stub_download("9000001", fit_zip)
    Activity.sync_now

    assert Activity.sole.original.attached?
    assert Activity.sole.track
  end

  test "sync processes a run that has an original but no track" do
    run = garmin_run(external_id: "9000001")
    attach_fit(run)
    stub_page(0, [fit_summary])

    Activity.sync_now

    assert_not_requested :get, /download-service/
    assert run.reload.track
  end

  test "sync skips unchanged runs that have an original and a track" do
    stub_page(0, [fit_summary])
    stub_download("9000001", fit_zip)
    Activity.sync_now
    Activity.sole.update!(splits: nil)
    stub_page(0, [fit_summary])

    Activity.sync_now

    assert_requested :get, /download-service/, times: 1
    assert_nil Activity.sole.splits
  end

  test "a sync that keeps working keeps counting as running" do
    stub_page(0, garmin_summaries(100))
    stub_page(100, garmin_summaries(1, first_id: 9200000))
    running = []

    Activity.sync_now do |page|
      travel 20.minutes if page[:start].zero?
      running << Profile.instance.syncing? if page[:start] == 100
    end
    travel_back

    assert_equal [true], running
  end

  test "a failed download does not fail the sync" do
    stub_page(0, [fit_summary])

    Activity.sync_now

    assert_nil Profile.instance.sync_error
    assert_predicate Profile.instance.synced_at, :present?
    assert_not Activity.sole.original.attached?
  end

  test "a failed parse does not fail the sync" do
    stub_page(0, [fit_summary])
    stub_download("9000001", zip("1_ACTIVITY.fit", "not a fit file"))

    Activity.sync_now

    assert_nil Profile.instance.sync_error
    assert_nil Activity.sole.track
  end
end
