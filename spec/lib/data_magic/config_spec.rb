require 'spec_helper'

describe DataMagic::Config do

  context "create" do
    it "works with zero args" do
      expect(DataMagic::Config.new).to_not be_nil
    end
    it "can set s3 client" do
      # TODO: mock s3
      s3_client = "s3 client"
      config = DataMagic::Config.new(s3: s3_client)
      expect(config.s3).to eq(s3_client)
    end
  end

  context "when loaded" do
    let(:config) {DataMagic::Config.new}

    after do
      config.clear_all
      #expect(DataMagic.client.indices.get(index: '_all')).to be_empty
    end

    context "#scoped_index_name" do
      it "includes environment prefix" do
        expect(config.scoped_index_name).to eq('test-city-data')
      end
    end
    it "has config data" do
      default_config = {"version"=>"cities100-2010", "index"=>"city-data", "api"=>"cities",
        "global_mapping"=>{"USPS"=>"state", "NAME"=>"name", "POP10"=>"population",
                           "INTPTLAT"=>"location.lat", "INTPTLONG"=>"location.lon"},
        "files"=>{"cities100.csv"=>{}},
        "data_path"=>"./sample-data"}
      expect(config.data).to eq(default_config)
    end

    it "has default page size" do
      expect(DataMagic::DEFAULT_PAGE_SIZE).to_not be_nil
      expect(config.page_size).to eq(DataMagic::DEFAULT_PAGE_SIZE)
    end

    describe "#update_indexed_config" do   #rename ... or do this in load_config or something
      context "after loading config" do
        let(:fixture_path) {"./spec/fixtures/import_with_dictionary"}
        before do
          config.load_datayaml(fixture_path)
        end
        it "should be true" do
          expect(config.update_indexed_config).to be true
        end
        it "should set new data_path" do
          expect(config.data_path).to eq(fixture_path)
        end

        it "twice should be false" do
          config.update_indexed_config
          expect(config.update_indexed_config).to be false
        end

      end
    end
  end
end
