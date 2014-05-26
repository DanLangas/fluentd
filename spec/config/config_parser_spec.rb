require "json"
require "config/helper"
require "fluent/config/error"
require "fluent/config/basic_parser"
require "fluent/config/literal_parser"
require "fluent/config/v1_parser"

describe Fluent::Config::V1Parser do
  include_context 'config_helper'

  def parse_text(text)
    basepath = File.expand_path(File.dirname(__FILE__) + '/../../')
    Fluent::Config::V1Parser.parse(text, '(test)', basepath, nil)
  end

  def root(*elements)
    if elements.first.is_a?(Fluent::Config::Element)
      attrs = {}
    else
      attrs = elements.shift || {}
    end
    Fluent::Config::Element.new('ROOT', '', attrs, elements)
  end

  def e(name, arg='', attrs={}, elements=[])
    Fluent::Config::Element.new(name, arg, attrs, elements)
  end

  describe 'attribute parsing' do
    it "parses attributes" do
      %[
        k1 v1
        k2 v2
      ].should be_parsed_as("k1"=>"v1", "k2"=>"v2")
    end

    it "allows attribute without value" do
      %[
        k1
        k2 v2
      ].should be_parsed_as("k1"=>"", "k2"=>"v2")
    end

    it "parses attribute key always string" do
      "1 1".should be_parsed_as("1" => "1")
    end

    [
      "_.%$!,",
      "/=~-~@`:?",
      "()*{}.[]",
    ].each do |v|
      it "parses a value with symbol #{v.inspect}" do
        "k #{v}".should be_parsed_as("k" => v)
      end
    end

    it "ignores spacing around value" do
      "  k1     a    ".should be_parsed_as("k1" => "a")
    end

    it "allows spaces in value" do
      "k1 a  b  c".should be_parsed_as("k1" => "a  b  c")
    end

    it "ignores comments after value" do
      "  k1 a#comment".should be_parsed_as("k1" => "a")
    end

    it "allows # in value if quoted" do
      '  k1 "a#comment"'.should be_parsed_as("k1" => "a#comment")
    end

    it "rejects characters after quoted string" do
      '  k1 "a" 1'.should be_parse_error
    end
  end

  describe 'element parsing' do
    it do
      "".should be_parsed_as(root)
    end

    it "accepts empty element" do
      %[
        <test>
        </test>
      ].should be_parsed_as(
        root(
          e("test")
        )
      )
    end

    it "accepts argument and attributes" do
      %[
        <test var>
          key val
        </test>
      ].should be_parsed_as(root(
          e("test", 'var', {'key'=>"val"})
        ))
    end

    it "accepts nested elements" do
      %[
        <test var>
          key 1
          <nested1>
          </nested1>
          <nested2>
          </nested2>
        </test>
      ].should be_parsed_as(root(
          e("test", 'var', {'key'=>'val'}, [
            e('nested1'),
            e('nested2')
          ])
        ))
    end

    [
      "**",
      "*.*",
      "1",
      "_.%$!",
      "/",
      "()*{}.[]",
    ].each do |arg|
      it "parses element argument #{arg.inspect}" do
        %[
          <test #{arg}>
          </test>
        ].should be_parsed_as(root(
            e("test", arg)
          ))
      end
    end

    it "parses empty element argument to nil" do
      %[
        <test >
        </test>
      ].should be_parsed_as(root(
          e("test", nil)
        ))
    end

    it "ignores spacing around element argument" do
      %[
        <test    a    >
        </test>
      ].should be_parsed_as(root(
          e("test", "a")
        ))
    end

    it "considers comments in element argument" do
      %[
        <test #a>
        </test>
      ].should be_parse_error
    end

    it "requires line_end after begin tag" do
      %[
        <test></test>
      ].should be_parse_error
    end

    it "requires line_end after end tag" do
      %[
        <test>
        </test><test>
        </test>
      ].should be_parse_error
    end
  end

  # port from test_config.rb
  describe '@include parsing' do
    TMP_DIR = File.dirname(__FILE__) + "/tmp/v1_config#{ENV['TEST_ENV_NUMBER']}"

    def write_config(path, data)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, "w") { |f| f.write data }
    end

    def prepare_config
      write_config "#{TMP_DIR}/config_test_1.conf", %[
        k1 root_config
        include dir/config_test_2.conf  #
        @include #{TMP_DIR}/config_test_4.conf
        include file://#{TMP_DIR}/config_test_5.conf
        @include config.d/*.conf
      ]
      write_config "#{TMP_DIR}/dir/config_test_2.conf", %[
        k2 relative_path_include
        @include ../config_test_3.conf
      ]
      write_config "#{TMP_DIR}/config_test_3.conf", %[
        k3 relative_include_in_included_file
      ]
      write_config "#{TMP_DIR}/config_test_4.conf", %[
        k4 absolute_path_include
      ]
      write_config "#{TMP_DIR}/config_test_5.conf", %[
        k5 uri_include
      ]
      write_config "#{TMP_DIR}/config.d/config_test_6.conf", %[
        k6 wildcard_include_1
        <elem1 name>
          include normal_parameter
        </elem1>
      ]
      write_config "#{TMP_DIR}/config.d/config_test_7.conf", %[
        k7 wildcard_include_2
      ]
      write_config "#{TMP_DIR}/config.d/config_test_8.conf", %[
        <elem2 name>
          @include ../dir/config_test_9.conf
        </elem2>
      ]
      write_config "#{TMP_DIR}/dir/config_test_9.conf", %[
        k9 embeded
        <elem3 name>
          nested nested_value
          include hoge
        </elem3>
      ]
      write_config "#{TMP_DIR}/config.d/00_config_test_8.conf", %[
        k8 wildcard_include_3
        <elem4 name>
          include normal_parameter
        </elem4>
      ]
    end

    it 'parses @include / include correctly' do
      prepare_config
      c = Fluent::Config.read("#{TMP_DIR}/config_test_1.conf", true)
      expect('root_config').to eq(c['k1'])
      expect('relative_path_include').to eq(c['k2'])
      expect('relative_include_in_included_file').to eq(c['k3'])
      expect('absolute_path_include').to eq(c['k4'])
      expect('uri_include').to eq(c['k5'])
      expect('wildcard_include_1').to eq(c['k6'])
      expect('wildcard_include_2').to eq(c['k7'])
      expect('wildcard_include_3').to eq(c['k8'])
      expect([
        'k1',
        'k2',
        'k3',
        'k4',
        'k5',
        'k8', # Because of the file name this comes first.
        'k6',
        'k7',
      ]).to eq(c.keys)

      elem1 = c.elements.find { |e| e.name == 'elem1' }
      expect(elem1).to be
      expect('name').to eq(elem1.arg)
      expect('normal_parameter').to eq(elem1['include'])

      elem2 = c.elements.find { |e| e.name == 'elem2' }
      expect(elem2).to be
      expect('name').to eq(elem2.arg)
      expect('embeded').to eq(elem2['k9'])
      expect(elem2.has_key?('include')).to be_false

      elem3 = elem2.elements.find { |e| e.name == 'elem3' }
      expect(elem2).to be
      expect('nested_value').to eq(elem3['nested'])
      expect('hoge').to eq(elem3['include'])
    end

    # TODO: Add uri based include spec
  end
end
