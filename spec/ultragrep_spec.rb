require "tmpdir"
require "yaml"

describe "Ultragrep" do
  def run(command, options={})
    result = `#{command} 2>&1`
    message = (options[:fail] ? "SUCCESS BUT SHOULD FAIL" : "FAIL")
    raise "[#{message}] #{result} [#{command}]" if $?.success? == !!options[:fail]
    result
  end

  def ultragrep(args, options={})
    run "#{Bundler.root}/bin/ultragrep #{args}", options
  end

  def write(file, content)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, content)
  end

  def fake_ultragrep_logs
    write "foo/host.1/a.log-#{date}", "Processing xxx at #{time}\n"
    write "bar/host.1/a.log-#{date}", "Processing yyy at #{time}\n"
    write "work/host.1/a.log-#{date}", %{{"time":"#{time}","session":"f6add2:a51f27"}\n}
  end

  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir, &example)
    end
  end

  describe "basics" do
    it "shows --help" do
      write ".ultragrep.yml", {"types" => {"fooo" => {}}}.to_yaml
      result = ultragrep("--help")
      result.should include "Usage: "
      result.should include "fooo"

      # alias
      ultragrep("-h").should include "Usage: "
      ultragrep("", :fail => true).should include "Usage: "
    end

    it "warns about missing config" do
      result = ultragrep("--help", :fail => true)
      result.should include "Please configure .ultragrep.yml,"
    end

    it "shows --version"
  end

  describe "grepping" do
    before do
      File.write(".ultragrep.yml", {"types" => { "app" => { "glob" => "foo/*/*", "format" => "app" }, "work" => { "glob" => "work/*/*", "format" => "work" } }, "default_type" => "app" }.to_yaml)
    end

    let(:date) { Time.now.strftime("%Y%m%d") }
    let(:time) { Time.now.strftime("%Y-%m-%d %H:%M:%S") }

    it "greps through 1 file" do
      write "foo/host.1/a.log-#{date}", "Processing xxx at #{time}\n"
      output =  ultragrep("at")
      output.strip.should == "# foo/host.1/a.log-#{date}\nProcessing xxx at #{time}\n--------------------------------------"
    end

    it "reads from config file" do
      run "mv .ultragrep.yml custom-location.yml"
      write "foo/host.1/a.log-#{date}", "Processing xxx at #{time}\n"
      output =  ultragrep("at --config custom-location.yml")
      output.strip.should include "xxx"
    end

    it "use different location via --type" do
      fake_ultragrep_logs
      output =  ultragrep("f6add2 --type work")
      output.should include "f6add2"
      output.should_not include "Processing"
    end
  end
end
