# Execute the actual formula install method with a tiny local Homebrew fixture.
# No brew calls, dependency downloads, or global state are involved.
require "pathname"
require "fileutils"

class Pathname
  def install(*sources)
    FileUtils.mkdir_p(to_s)
    sources.each { |source| FileUtils.cp_r(source, to_s) }
  end
end

class Formula
  def self.test
    # Do not execute the formula's Homebrew test DSL during fixture installation.
  end

  def self.method_missing(*)
    # Homebrew metadata and test DSL are irrelevant to this install fixture.
  end

  def self.[](name)
    dependency = Object.new
    path = Pathname.new(ENV.fetch("FIXTURE_PREFIX"))/"opt/#{name}/bin"
    dependency.define_singleton_method(:opt_bin) { path }
    dependency
  end

  def libexec
    Pathname.new(ENV.fetch("FIXTURE_PREFIX"))/"Cellar/caulking/1/libexec"
  end

  def opt_libexec
    Pathname.new(ENV.fetch("FIXTURE_PREFIX"))/"opt/caulking/libexec"
  end

  def bin
    path = Pathname.new(ENV.fetch("FIXTURE_PREFIX"))/"bin"
    FileUtils.mkdir_p(path)
    path
  end

  def chmod(mode, path)
    FileUtils.chmod(mode, path)
  end
end

load ARGV.fetch(0)
Caulking.new.install
