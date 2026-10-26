require "test_helper"

class ThemesControllerTest < ActionDispatch::IntegrationTest
  test "stores the choice in a long-lived cookie and redirects back" do
    patch theme_path, params: {theme: "dark"}, headers: {"HTTP_REFERER" => "http://www.example.com/runs?sort=km"}

    assert_redirected_to "http://www.example.com/runs?sort=km"
    assert_equal "dark", cookies[:theme]
    assert_match(/theme=dark;.*expires=.*; .*httponly/i, response.headers["Set-Cookie"])
    assert_match(/samesite=lax/i, response.headers["Set-Cookie"])
  end

  test "falls back to the home page without a referer" do
    patch theme_path, params: {theme: "light"}

    assert_redirected_to root_path
    assert_equal "light", cookies[:theme]
  end

  test "ignores an invalid value" do
    patch theme_path, params: {theme: "purple"}

    assert_redirected_to root_path
    assert_nil cookies[:theme]
  end

  test "an invalid value leaves the existing choice alone" do
    patch theme_path, params: {theme: "dark"}
    patch theme_path, params: {theme: "<script>"}

    assert_equal "dark", cookies[:theme]
  end

  test "never redirects to another host" do
    patch theme_path, params: {theme: "dark"}, headers: {"HTTP_REFERER" => "https://evil.example/steal"}

    assert_redirected_to root_path
  end

  test "the layout renders the choice on the html element and marks the switch" do
    {nil => "system", "system" => "system", "light" => "light", "dark" => "dark", "bogus" => "system"}.each do |cookie, expected|
      cookies[:theme] = cookie if cookie
      cookies.delete(:theme) unless cookie

      get "/overview"

      assert_select "html[data-theme=?]", expected
      assert_select "[role=group][aria-label=Theme] button[aria-pressed=true]", count: 1
      assert_select "[role=group][aria-label=Theme] button[aria-pressed=true][aria-label=?]", expected.capitalize
      assert_select "[role=group][aria-label=Theme] button", count: 3
    end
  end

  test "the switch forms are full page submissions" do
    get "/overview"

    assert_select "form[action=?][method=post][data-turbo=false]", theme_path, count: 3
    assert_select "form input[name=_method][value=patch]", minimum: 3
  end
end
