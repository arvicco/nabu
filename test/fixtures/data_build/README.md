# data_build golden fixtures

`datapackage.json` is a GOLDEN OUTPUT file, not an upstream sample: the
byte-exact manifest `Nabu::DataBuild::Manifest.generate` produces for the
suite's fake feature (`DataBuildFake.golden_manifest_args` in
`test/support/data_build_fake.rb` — the single shared source of the inputs,
so test and fixture cannot drift apart).

Regenerate after an INTENDED manifest-shape change (and say why in the
commit):

    bundle exec ruby -Itest -Ilib -e 'require "test_helper";
      File.write("test/fixtures/data_build/datapackage.json",
                 Nabu::DataBuild::Manifest.generate(**DataBuildFake.golden_manifest_args))'
