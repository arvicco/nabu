# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Re-packs the trimmed PNA fixture members (test/fixtures/pna/) into the
# two archives the Zenodo v3 record serves, under upstream's own member
# layout (Networks/…, SupplementaryData/…), plus the README.txt verbatim —
# the workdir shape Nabu::Adapters::Pna#fetch lands.
module PnaFixtureZips
  ARCHIVES = { "Networks.zip" => "Networks", "SupplementaryData.zip" => "SupplementaryData" }.freeze

  module_function

  # { filename => bytes } for the three record files.
  def bodies(fixtures)
    Dir.mktmpdir do |dir|
      ARCHIVES.to_h do |zip_name, top|
        zip_path = File.join(dir, zip_name)
        Nabu::Shell.run("zip", "-q", "-r", "-X", zip_path, top, chdir: fixtures)
        [zip_name, File.binread(zip_path)]
      end.merge("README.txt" => File.binread(File.join(fixtures, "README.txt")))
    end
  end

  def pack!(fixtures, workdir)
    bodies(fixtures).each { |name, bytes| File.binwrite(File.join(workdir, name), bytes) }
  end
end
