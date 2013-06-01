require "tmpdir"
require "yaml"
require "ultragrep"

describe Ultragrep do
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

  def test_time_is_found(success, ago, command, options={})
    time = (Time.now - ago).strftime(time_format)
    write "foo/host.1/a.log-#{date}", "Processing xxx at #{time}\n"
    output = ultragrep("at #{command}", options)
    if success
      output.should include "Processing"
    else
      output.strip.should == ""
    end
  end

  def test_is_found(success, command)
    test_time_is_found(success, 0, command)
  end

  describe "CLI" do
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

      it "shows --version" do
        ultragrep("--version").should =~ /Ultragrep version \d+\.\d+\.\d+/
      end
    end

    describe "grepping" do
      before do
        File.write(".ultragrep.yml", {"types" => { "app" => { "glob" => "foo/*/*", "format" => "app" }, "work" => { "glob" => "work/*/*", "format" => "work" } }, "default_type" => "app" }.to_yaml)
      end

      let(:date) { Time.now.strftime("%Y%m%d") }
      let(:time_format) { "%Y-%m-%d %H:%M:%S" }
      let(:time) { Time.now.strftime(time_format) }
      let(:day) { 24 * hour }
      let(:hour) { 60 * 60 }

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
        output = ultragrep("f6add2 --type work")
        output.should include "f6add2"
        output.should_not include "Processing"
      end

      context "default range" do
        let(:time_since_start_of_day) { Time.now.to_i % day }

        before do
          pending "to close to day border, tests would fail" if time_since_start_of_day < 1.5 * hour
        end

        context "start" do
          it "ignores older then start of day" do
            test_time_is_found(true, time_since_start_of_day - hour, "")
          end

          it "finds after start of day" do
            test_time_is_found(false, time_since_start_of_day + hour, "")
          end
        end

        context "end" do
          it "ignores after current time" do
            pending "does not seem to work" do
              test_time_is_found(false, -hour, "")
            end
          end

          it "find before current time" do
            test_time_is_found(true, hour, "")
          end
        end
      end

      context "--start" do
        let(:time) { Time.now - (2 * hour) }

        it "blows up with incorrect time format" do
          ultragrep("--start asdadasdsd", :fail => true)
        end

        context "with nice format" do
          it "ignores things before start" do
            test_time_is_found(false, 3 * hour, "--start '#{time.strftime("%Y-%m-%d %H:%M:%S")}'")
          end

          it "finds things after start" do
            test_time_is_found(true, hour, "--start '#{time.strftime("%Y-%m-%d %H:%M:%S")}'")
          end
        end

        context "wit integer" do
          it "ignores things before start" do
            test_time_is_found(false, 3 * hour, "--start #{time.to_i}")
          end

          it "finds things after start" do
            test_time_is_found(true, hour, "--start #{time.to_i}")
          end
        end
      end

      context "--host" do
        before do
          # do not blow up because of missing files
          write "foo/host.2/a.log-#{date}", "UNMATCHED"
          write "foo/host.3/a.log-#{date}", "UNMATCHED"
        end

        context "single" do
          it "finds wanted host" do
            test_is_found(true, "--host host.1")
          end

          it "ignores unwanted host" do
            test_is_found(false, "--host host.2")
          end
        end

        context "multiple" do
          it "find wanted host" do
            test_is_found(true, "--host host.2 --host host.1 --host host.2")
          end

          it "ignores unwanted host" do
            test_is_found(false, "--host host.2 --host host.3")
          end
        end
      end

      context "--progress" do
        before do
          write "foo/host.1/a.log-#{date}", "UNMATCHED"
        end

        it "shows file list" do
          result = ultragrep("xxx --progress")
          result.should include "searching for regexps: 'xxx' from "
          result.should include "searching foo/host.1/a.log-#{date}"
        end

        it "does not show file list without" do
          result = ultragrep("xxx")
          result.should_not include "searching for regexps: 'xxx' from "
          result.should_not include "searching foo/host.1/a.log-#{date}"
        end
      end
    end
  end

  describe ".parse_time" do
    it "parses int" do
      expected = Time.now.to_i
      Ultragrep.send(:parse_time, expected.to_s).to_i.should == expected
    end

    it "parses string" do
      Ultragrep.send(:parse_time, "2013-01-01").to_i.should == 1357027200
    end

    it "parses weird string" do
      Ultragrep.send(:parse_time, "20130101").to_i.should == 1357027200
    end

    it "blows up on invalid time" do
      expect{
        Ultragrep.send(:parse_time, "asdasdas")
      }.to raise_error
    end
  end
end
