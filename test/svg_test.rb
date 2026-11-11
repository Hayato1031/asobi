# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class SvgTest < Minitest::Test
  def test_document_white_paper_and_viewbox
    svg = circle.to_svg(margin: 5)
    assert svg.start_with?(%(<svg xmlns="http://www.w3.org/2000/svg" viewBox="-15 -15 30 30"))
    assert_includes svg, %(<rect x="-15" y="-15" width="30" height="30" fill="white"/>)
    assert_includes svg, %(<circle r="10"/>)
    assert svg.end_with?("</svg>\n")
  end

  def test_auto_margin_and_background_choices
    view = Asobi::SVG.view(circle)
    assert_operator view[0], :<, -10
    refute_includes circle.to_svg(background: nil), "<rect"
    assert_includes circle.to_svg(background: :black), %(fill="black")
  end

  def test_on_sets_the_background_of_svg_text_and_saved_files
    svg = circle.to_svg(on: :black)
    assert_includes svg, %(fill="black")
    refute_includes circle.to_svg(on: nil), "<rect"

    Dir.mktmpdir do |dir|
      path = File.join(dir, "circle.svg")
      circle.save(path, on: :black)
      assert_equal svg, File.read(path)
    end
  end

  def test_paper
    svg = circle.to_svg(paper: [800, 600])
    assert_includes svg, %(viewBox="-400 -300 800 600")
    assert_includes svg, %(width="800" height="600")
  end

  def test_helpers_for_the_player
    view = Asobi::SVG.view(Asobi::Box.new(-1.0, -2.0, 3.0, 4.0), margin: 0)
    assert_equal [-1.0, -2.0, 4.0, 6.0], view
    assert_includes Asobi::SVG.open_tag(view), %(viewBox="-1 -2 4 6")
    assert_equal "", Asobi::SVG.background(view, :none)
    assert_equal Asobi::SVG.view(nothing), Asobi::SVG.view(nil)
  end

  def test_fragment_has_no_svg_tag
    refute_includes circle.beside(square).svg, "<svg"
  end

  def test_transform_output
    assert_includes circle.move(right: 3).svg, %(transform="translate(3 0)")
    assert_includes circle.rotate(90).svg, %(transform="matrix(0 1 -1 0 0 0)")
  end
end
