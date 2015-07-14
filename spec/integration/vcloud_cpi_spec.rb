require 'spec_helper'

describe VCloudCloud::Cloud do
  before(:all) do
    @host          = ENV['BOSH_VCLOUD_CPI_URL']     || raise("Missing BOSH_VCLOUD_CPI_URL")
    @user          = ENV['BOSH_VCLOUD_CPI_USER']     || raise("Missing BOSH_VCLOUD_CPI_USER")
    @password      = ENV['BOSH_VCLOUD_CPI_PASSWORD'] || raise("Missing BOSH_VCLOUD_CPI_PASSWORD")
    @vlan          = ENV['BOSH_VCLOUD_CPI_NET_ID']         || raise("Missing BOSH_VCLOUD_CPI_NET_ID")
    @stemcell_path = ENV['BOSH_VCLOUD_CPI_STEMCELL']     || raise("Missing BOSH_VCLOUD_CPI_STEMCELL")
    @org           = ENV['BOSH_VCLOUD_CPI_ORG']     || raise("Missing BOSH_VCLOUD_CPI_ORG")
    @vdc           = ENV['BOSH_VCLOUD_CPI_VDC']     || raise("Missing BOSH_VCLOUD_CPI_VDC")
    @vapp_catalog  = ENV['BOSH_VCLOUD_CPI_VAPP_CATALOG'] || raise("Missing BOSH_VCLOUD_CPI_VAPP_CATALOG")
    @vapp_name     = ENV['BOSH_VCLOUD_CPI_VAPP_NAME'] || raise("Missing BOSH_VCLOUD_CPI_VAPP_NAME")
    @media_catalog = ENV['BOSH_VCLOUD_CPI_MEDIA_CATALOG']         || raise("Missing BOSH_VCLOUD_CPI_MEDIA_CATALOG")
    @media_storage_prof  = ENV['BOSH_VCLOUD_CPI_MEDIA_STORAGE_PROFILE']     || raise("Missing BOSH_VCLOUD_CPI_MEDIA_STORAGE_PROFILE")
    @vapp_storage_prof  = ENV['BOSH_VCLOUD_CPI_VAPP_STORAGE_PROFILE']     || raise("Missing BOSH_VCLOUD_CPI_VAPP_STORAGE_PROFILE")
    @metadata_key  = ENV['BOSH_VCLOUD_CPI_VM_METADATA_KEY']     || raise("Missing BOSH_VCLOUD_CPI_VM_METADATA_KEY")
    @target_ip1     = ENV['BOSH_VCLOUD_CPI_IP']     || raise("Missing BOSH_VCLOUD_CPI_IP")
    @target_ip2     = ENV['BOSH_VCLOUD_CPI_IP2']     || raise("Missing BOSH_VCLOUD_CPI_IP2")
    @target_ips     = [@target_ip1, @target_ip2]
    @netmask       = ENV['BOSH_VCLOUD_CPI_NETMASK'] || raise("Missing BOSH_VCLOUD_CPI_NETMASK")
    @dns           = ENV['BOSH_VCLOUD_CPI_DNS']         || raise("Missing BOSH_VCLOUD_CPI_DNS")
    @gateway       = ENV['BOSH_VCLOUD_CPI_GATEWAY']     || raise("Missing BOSH_VCLOUD_CPI_GATEWAY")

    # not required
    @ntp           = ENV['BOSH_VCLOUD_CPI_NTP_SERVER'] || '0.us.pool.ntp.org'
  end

  before(:all) do
    # randomize catalog names to ensure this CPI can create them on demand
    @vapp_catalog = "#{@vapp_catalog}_#{Process.pid}_#{rand(1000)}"
    @media_catalog = "#{@media_catalog}_#{Process.pid}_#{rand(1000)}"
    @cpis = []
    @network_specs = []
    @target_ips.each do |ip|
      @cpis << described_class.new(
          'agent' => {
              'ntp' => @ntp,
          },
          'vcds' => [{
                         'url' => @host,
                         'user' => @user,
                         'password' => @password,
                         'entities' => {
                             'organization' => @org,
                             'virtual_datacenter' => @vdc,
                             'vapp_catalog' => @vapp_catalog,
                             'media_catalog' => @media_catalog,
                             'media_storage_profile' => @media_storage_prof,
                             'vapp_storage_profile' => @vapp_storage_prof,
                             'vm_metadata_key' => @metadata_key,
                             'description' => 'BOSH on vCloudDirector',
                         }
                     }]
      )
      @network_specs << {
          "static" => {
              "ip" => ip,
              "netmask" => @netmask,
              "cloud_properties" => {"name" => @vlan},
              "default" => ["dns", "gateway"],
              "dns" => @dns,
              "gateway" => @gateway
          }
      }
    end

    @cpi = @cpis[0]
  end

  let(:resource_pool) {
    {
        'ram' => 1024,
        'disk' => 2048,
        'cpu' => 1,
    }
  }

  let(:vm_env) {
    {'vapp' => @vapp_name}
  }

  let(:random_vm_name) {
    "#{@vapp_name}_intergration_#{Process.pid}_#{rand(1000)}"
  }

  let(:client) {
    @cpi.client
  }

  before(:all) do
    Dir.mktmpdir do |temp_dir|
      output = `tar -C #{temp_dir} -xzf #{@stemcell_path} 2>&1`
      raise "Corrupt image, tar exit status: #{$?.exitstatus} output: #{output}" if $?.exitstatus != 0
      @stemcell_id = @cpi.create_stemcell("#{temp_dir}/image", nil)
    end
  end

  after(:all) do
    @cpi.delete_stemcell(@stemcell_id) if @stemcell_id
    client = @cpi.client
    VCloudCloud::Test::delete_catalog_if_exists(client, @vapp_catalog)
    VCloudCloud::Test::delete_catalog_if_exists(client, @media_catalog)
  end

  before { @vm_ids = [] }

  after {
    @vm_ids.each do |vm_id|
      @cpi.delete_vm(vm_id) if vm_id
    end
  }

  before { @disk_ids = [] }
  after {
    @disk_ids.each do |disk_id|
      @cpi.delete_disk(disk_id) if disk_id
    end
  }

  context "when there is no error in create_vm" do
    it 'should create vm and reconfigure network' do
      vm_id = @cpi.create_vm random_vm_name, @stemcell_id, resource_pool, @network_specs[0], [], vm_env
      vm_id.should_not be_nil
      @vm_ids << vm_id
      has_vm = @cpi.has_vm? vm_id
      has_vm.should be_true

      expect {@cpi.configure_networks vm_id, @network_specs[1]}.to raise_error Bosh::Clouds::NotSupported
      disk_id = @cpi.create_disk(2048, {}, vm_id)
      disk_id.should_not be_nil
      @disk_ids << disk_id

      @cpi.attach_disk vm_id, disk_id
      @cpi.detach_disk vm_id, disk_id

      @cpi.reboot_vm vm_id
    end
  end

  context "when received exception during create_vm" do

    before do
      allow(Bosh::Retryable).to receive(:new).and_return(retryable)
      allow(retryable).to receive(:retryer).and_yield(0, :error)
    end

    let(:retryable) { double('Bosh::Retryable') }

    context "when target vapp exists" do
      it 'should remove the tmp vapp' do
        # First successfully create the target vapp
        vm_id = @cpi.create_vm random_vm_name, @stemcell_id, resource_pool, @network_specs[0], [], vm_env
        vm_id.should_not be_nil
        @vm_ids << vm_id

        exceptionMsg = 'PowerOn Failed!'
        VCloudCloud::Steps::PowerOn.any_instance.stub(:perform).and_raise(exceptionMsg)

        begin
          @cpi.create_vm random_vm_name, @stemcell_id, resource_pool, @network_specs[1], [], vm_env
          fail 'create_vm should fail'
        rescue => ex
          expect(ex.to_s).to match(Regexp.new(exceptionMsg))
        end

        # The target vapp should exist despite that the tmp vapp is deleted
        vapp_name = @vapp_name
        client.flush_cache  # flush cached vdc which contains vapp list
        vapp = client.vapp_by_name vapp_name
        vapp.name.should eq vapp_name
        vapp.vms.size.should eq 1
      end

      it 'concurrent config should remove the tmp vapps' do
        vm_id = @cpi.create_vm random_vm_name, @stemcell_id, resource_pool, @network_specs[0], [], vm_env
        vm_id.should_not be_nil
        @vm_ids << vm_id

        exceptionMsg = 'Recompose Failed!'
        VCloudCloud::Steps::Recompose.any_instance.stub(:perform).and_raise(exceptionMsg)
        begin
          @cpi.create_vm random_vm_name, @stemcell_id, resource_pool, @network_specs[1], [], vm_env
          fail 'create_vm should fail'
        rescue => ex
          expect(ex.to_s).to match(Regexp.new(exceptionMsg))
        end

        # The target vapp should exist despite that the tmp vapps are deleted
        vapp_name = @vapp_name
        client.flush_cache  # flush cached vdc which contains vapp list
        vapp = client.vapp_by_name vapp_name
        vapp.name.should eq vapp_name
        vapp.vms.size.should eq 1

        client.invoke_and_wait :post, vapp.power_off_link
        params = VCloudSdk::Xml::WrapperFactory.create_instance 'UndeployVAppParams'
        client.invoke_and_wait :post, vapp.undeploy_link, :payload => params
        link = vapp.remove_link true
        client.invoke_and_wait :delete, link
      end
    end

    context "when target vapp does not exist" do
      it 'the tmp vapp should not exist' do
        exceptionMsg = 'PowerOn Failed!'
        VCloudCloud::Steps::PowerOn.any_instance.stub(:perform).and_raise(exceptionMsg)

        begin
          @cpi.create_vm random_vm_name, @stemcell_id, resource_pool, @network_specs[0], [], vm_env
          fail 'create_vm should fail'
        rescue => ex
          expect(ex.to_s).to match(Regexp.new(exceptionMsg))
        end

        # The tmp vapp is renamed to the target vapp
        vapp_name = @vapp_name
        client.flush_cache  # flush cached vdc which contains vapp list
        vapp = client.vapp_by_name vapp_name
        vapp.name.should eq vapp_name
        client.invoke_and_wait :delete, vapp.remove_link

        exceptionMsg = 'Recompose Failed!'
        VCloudCloud::Steps::Recompose.any_instance.stub(:perform).and_raise(exceptionMsg)

        begin
          # The tmp vapp is not renamed to the target because recomposing failed
          # Instantiate rollback will delete the tmp vapp
          @cpi.create_vm random_vm_name, @stemcell_id, resource_pool, @network_specs[1], [], vm_env
          fail 'create_vm should fail'
        rescue => ex
          expect(ex.to_s).to match(Regexp.new(exceptionMsg))
        end
      end
    end
  end
end
