require "test_helper"

class ControlsHelperTest < ActionView::TestCase
  test "segments are pressed buttons in a labelled group" do
    html = button_group("Mode") { segment("A", selected: true, value: "a") + segment("B", value: "b") }

    assert_select Nokogiri::HTML.fragment(html), "[role=group][aria-label=Mode] button[type=button]", count: 2
    assert_includes html, 'aria-pressed="true"'
    assert_includes html, 'aria-pressed="false"'
  end

  test "a segment with an href is a link marked current when selected" do
    assert_includes segment("A", selected: true, href: "/x"), 'aria-current="page"'
    assert_not_includes segment("A", href: "/x"), "aria-current"
  end

  test "toggle buttons report pressed" do
    assert_includes toggle_button("A", pressed: true, href: "/x"), 'aria-pressed="true"'
    assert_includes toggle_button("A"), "<button"
  end

  test "action buttons are links" do
    assert_includes action_button("Go", "/x"), 'href="/x"'
  end
end
