require "test_helper"

class PagesTest < ActionDispatch::IntegrationTest
  test "root redirects to overview" do
    get "/"

    assert_redirected_to "/overview"
  end

  test "pages render" do
    %w[/overview /overview/2024 /overview/2024/3 /overview/2024/03 /overview/2024/09 /overview/2024/12 /pace_trend].each do |path|
      get path

      assert_response :success, path
    end
  end

  test "overview constrains year and month" do
    get "/overview/24"
    assert_response :not_found

    %w[/overview/2024/123 /overview/2024/13 /overview/2024/0].each do |path|
      get path

      assert_response :not_found, path
    end
  end
end
