# ---------------------------------------------------------------------------- #
# Copyright 2010-2012, C12G Labs S.L                                           #
#                                                                              #
# Licensed under the Apache License, Version 2.0 (the "License"); you may      #
# not use this file except in compliance with the License. You may obtain      #
# a copy of the License at                                                     #
#                                                                              #
# http://www.apache.org/licenses/LICENSE-2.0                                   #
#                                                                              #
# Unless required by applicable law or agreed to in writing, software          #
# distributed under the License is distributed on an "AS IS" BASIS,            #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.     #
# See the License for the specific language governing permissions and          #
# limitations under the License.                                               #
# ---------------------------------------------------------------------------- #

require 'rubygems'
require 'uuidtools'
require 'xmlrpc/client'
require 'fileutils'
require 'open-uri'

require 'rubygems'
require 'nokogiri'


module XenAPI
    class XenAPIConnection
        attr_reader :host, :user, :password

        def initialize(host, user, password)
            @host=host
            @url="http://#{host}"
            @user=user
            @password=password
            @token=nil
            @conn=nil
        end

        def conn
            if !@conn
                @conn=XMLRPC::Client.new2(@url)
                @conn.http_header_extra={"User-Agent"=>"XenCenter/6.0.0"}
            end

            @conn
        end

        def login
            res=conn.call_async('session.login_with_password', @user, @password, "1.9")
            if res['Status']=='Success'
                @token=res['Value']
            else
                raise "Could not authenticate with XenAPI server"
                @token=nil
            end
        end

        def call(method, *args)
            login if !@token

            params=[@token]+args
            XenAPIResponse.new conn.call_async(method, *params)
        end
    end

    class XenAPIResponse
        attr_reader :status, :value, :error

        def initialize(response)
            @response=response

            @status=response['Status']
            @value=response['Value']
            @error=response['ErrorDescription']

            if error?
                STDERR.puts @error.inspect
                raise "Error in XenAPI call: #{@error.inspect}"
            end
        end

        def ok?
            @status=='Success'
        end

        def error?
            !ok?
        end
    end

    class XenAPIObject
        attr_accessor :info, :reference

        # set the connection for all children objects
        #
        # @param [XenAPIConnection] connection to the XenAPI server
        def self.set_connection(conn)
            @@conn=conn
        end

        def base_info
            {}
        end

        def self.new_with_defaults
            self.new(self.base_info)
        end

        def initialize(info={})
            @info=info
            @reference=nil
        end

        # connection object (for instances)
        def conn
            @@conn
        end

        # connection object (for class methods)
        def self.conn
            @@conn
        end

        # This method return a string with the object name for XenAPI.
        # It should be redefined by all the children with the correct one.
        def self.api_name
            'api_name'
        end

        # make api_name work for instances
        def api_name
            self.class.api_name
        end

        # convenience method to make XenAPI calls (class)
        def self.xen(method, *args)
            conn.call("#{api_name}.#{method}", *args)
        end

        # convenience method to make XenAPI calls (instance)
        def xen(method, *args)
            self.class.xen(method, *args)
        end

        # create a new object and add reference information
        def self.new_with_ref(ref, info)
            object=self.new(info)
            object.reference=ref
            object
        end

        # gets an array aff all VMs
        def self.get_all
            res=xen("get_all_records")
            
            return res if res.error?

            res.value.map do |reference, info|
                self.new_with_ref(reference, info)
            end
        end

        # gets an array with all the references
        def self.get_references
            res=xen("get_all")

            return res if res.error?

            res.value
        end

        # get the object given its reference
        def self.get_by_reference(ref)
            res=xen("get_record", ref)

            return res if res.error?

            self.new_with_ref(ref, res.value)
        end

        def refresh
            object=self.class.get_by_reference(self.reference)

            return object if XenAPIResponse===object

            self.info=object.info
        end

        # get the object given its reference
        def self.get_by_uuid(uuid)
            res=xen("get_by_uuid", uuid)

            return res if res.error?

            self.new_with_ref(res.value, {})
        end

        def self.find_by_name(name)
            res=self.get_all

            return res if XenAPIResponse===res

            res.select do |object|
                name===object.info['name_label']
            end
        end

        def set_name(name)
            info['name_label']=name
        end

        def update(key, value)
            xen("set_#{key}", @reference, value)
        end

        def update_name(name)
            update('name_label', name)
        end

        def create
            res=xen("create", @info)

            return res if res.error?

            self.reference=res.value
        end

        def destroy
            res=xen("destroy", @reference)

            return res if res.error?
        end
    end

    module Monitorizable
        def get_monitoring_data
            if !@info['uuid']
                self.refresh
            end

            type=self.class.to_s.downcase.split(':').last

            uuid=@info['uuid']
            rrd=RRDData.new(conn.host, conn.user, conn.password)
            rrd.get_data(type, uuid)
            rrd.data
        end
    end

    class VM < XenAPIObject
        include Monitorizable

        def self.base_info
            {
                'actions_after_crash' => 'destroy',
                'actions_after_reboot' => 'restart',
                'actions_after_shutdown' => 'destroy',
                'affinity' => '',
                'blocked_operations' => {},
                'ha_always_run' => false,
                'ha_restart_priority' => '',
                'HVM_boot_params' => {},
                'HVM_boot_policy' => '',
                'is_a_template' => false,
                'memory_dynamic_min' => 1024,
                'memory_dynamic_max' => 1024,
                'memory_static_min' => '0',
                'memory_static_max' => 1024,
                'memory_target' => 1024,
                'name_description' => '',
                'name_label' => 'one vm',
                'other_config' => {},
                'PCI_bus' => '',
                'platform' => {'acpi' => 'true', 'apic' => 'true', 'pae' => 'true',
                             'viridian' => 'true', 'timeoffset' => '0'},
                'PV_args' => '',
                'PV_bootloader' => '',
                'PV_bootloader_args' => '',
                'PV_kernel' => '',
                'PV_legacy_args' => '',
                'PV_ramdisk' => '',
                'recommendations' => '',
                'tags' => [],
                'user_version' => '0',
                'VCPUs_at_startup' => '1',
                'VCPUs_max' => '1',
                'VCPUs_params' => {},
                'xenstore_data' => {}
            }
        end

        def initialize(info={})
            super(info)
        end

        def self.api_name
            'VM'
        end

        def start
            res=xen("start", self.reference, false, false)

            return res if res.error?

            self.reference
        end

        def hard_shutdown
            res=xen("hard_shutdown", self.reference)

            return res if res.error?

            self.reference
        end

        def suspend
            res=xen("suspend", self.reference)

            return res if res.error?

            self.reference
        end

        def resume
            res=xen("resume", self.reference, false, false)

            return res if res.error?

            self.reference
        end

        def set_memory(mem)
            info['memory_dynamic_min']=mem.to_s
            info['memory_dynamic_max']=mem.to_s
            info['memory_static_max']=mem.to_s
            info['memory_target']=mem.to_s
        end

        def set_cpu(cpu)
            info['VCPUs_at_startup']=cpu.to_s
            info['VCPUs_max']=cpu.to_s
        end

        def add_disk(vdi, pos, cdrom=false)
            vbd=VBD.new_with_defaults
            vbd.set_vm(self)
            vbd.set_vdi(vdi)
            vbd.set_device(pos)
            vbd.set_cdrom if cdrom
            STDERR.puts vbd.info.inspect
            vbd.create
        end

    end

    class SR < XenAPIObject
        attr_accessor :share

        def self.api_name
            'SR'
        end

        def initialize(info={})
            super(info)

            @share=''
        end

        def scan
            xen("scan", reference)
        end

        def add_image(file)
            refresh if info.empty?

            uuid=UUIDTools::UUID.random_create.to_s

            fname="#{@share}/#{info['uuid']}/#{uuid}.raw"

            FileUtils.cp(file, fname)
            FileUtils.chmod(0666, fname)

            scan
            VDI.get_by_uuid(uuid)
        end

        def create_vdi(name, size)
                vdi=VDI.new_with_defaults
                vdi.info.mege!({
                    'SR' => @reference,
                    'name_label' => name,
                    'virtual_size' => size.to_s
                })

                vdi.create
        end
    end

    class VDI < XenAPIObject
        def self.api_name
            'VDI'
        end

        def self.base_info
                #'name_label' => name_label,
                #'SR' => sr_ref,
                #'virtual_size' => str(virtual_size),
            {
                'name_description' => '',
                'type' => 'User',
                'sharable' => false,
                'read_only' => false,
                'xenstore_data' => {},
                'other_config' => {},
                'sm_config' => {},
                'tags' => []
            }
        end

        def copy(sr)
            res=xen("copy", @reference, sr.reference)

            res if res.error?
            
            VDI.new_with_ref(res.value, {})
        end

        def clone
            res=xen("clone", @reference)

            res if res.error?
            
            VDI.new_with_ref(res.value, {})
        end
    end

    class VBD < XenAPIObject
        def self.api_name
            'VBD'
        end

        def self.base_info
            {
                'VM' => '',
                'VDI' => '',
                'device' => 'hda',
                'bootable' => true,
                'mode' => 'RW',
                'type' => 'disk',
                'unpluggable' => true,
                'empty' => false,
                'other_config' => {},
                'userdevice' => '0',
                'qos_algorithm_type' => '',
                'qos_algorithm_params' => {},
                'qos_supported_algorithms' => []
            }
        end

        def set_vm(vm)
            info['VM']=vm.reference
        end

        def set_vdi(vdi)
            info['VDI']=vdi.reference
        end

        def set_device(device)
            info['device']=device.to_s
            info['userdevice']=device.to_s
        end
        
        def set_type(type)
            info['type']=type
        end

        def set_bootable(bootable)
            info['bootable']=bootable
        end

        def set_mode(mode)
            info['mode']=mode
        end

        def set_cdrom
            set_type('cd')
            set_bootable(false)
            set_mode('RO')
        end
    end

    class VIF < XenAPIObject
        def self.api_name
            'VIF'
        end

        def self.base_info
            {
                'device' => '0',
                'network' => '',
                'VM' => '',
                'MAC' => '00:02:00:00:00:00',
                'MTU' => '1500',
                'other_config' => {},
                'qos_algorithm_type' => '',
                'qos_algorithm_params' => {}
            }
        end

        def set_device(device)
            @info['device']=device.to_s
        end

        def set_network(network)
            @info['network']=network.reference
        end

        def set_vm(vm)
            @info['VM']=vm.reference
        end

        def set_mac(mac)
            @info['MAC']=mac
        end
    end

    class VIFMetrics < XenAPIObject
        def self.api_name
            'VIF_metrics'
        end
    end

    class Network < XenAPIObject
        def self.api_name
            'network'
        end
    end

    class Host < XenAPIObject
        include Monitorizable

        def self.api_name
            'host'
        end
    end

    class HostMetrics < XenAPIObject
        def self.api_name
            'host_metrics'
        end
    end

    class HostCPU < XenAPIObject
        def self.api_name
            'host_cpu'
        end
    end

    class Console < XenAPIObject
        def self.api_name
            'console'
        end
    end

    class RRDData
        attr_reader :data, :xen_data

        def initialize(host, user, password, last_time=nil)
            time=last_time||(Time.now.to_i-10)

            http=open(
                "http://#{host}/rrd_updates?start=#{time}&host=true&cf=AVERAGE",
                :http_basic_authentication => [user, password])
            xml=http.read
            http.close

            @xml=Nokogiri::XML(xml)
            @data={}

            extract_data

            @xml=nil
        end

        def extract_data
            keys=@xml.xpath('/xport/meta/legend/entry').map do |item|
                item.text
            end

            #xpath='/rrd/rra[pdp_per_row=1 and cf="AVERAGE"]/database/row[last()]/v'
            xpath='/xport/data/row[1]/v'
            data=@xml.xpath(xpath).map { |item| item.text }

            @xen_data={}
            keys.each_with_index do |key, index|
                @xen_data[key]=data[index]
            end
        end

        def get_data(type, uuid)
            @data={}
            @xen_data.each do |key, value|
                if key.match(/^AVERAGE:#{type}:#{uuid}:(.*)$/)
                    name=$1
                    data[name]=value
                end
            end

            extract_cpu
        end

        def extract_cpu
            cpu_keys=@data.keys.select {|key| key.match(/^cpu\d+$/) }
            num_cpu=cpu_keys.length

            used_cpu=0.0
            cpu_keys.each {|cpu| used_cpu+=@data[cpu].to_f }
            used_cpu*=100

            @data['used_cpu']=used_cpu
            @data['total_cpu']=num_cpu*100
            @data['free_cpu']=@data['total_cpu']-used_cpu
        end

        def extract_memory
            @data['total_memory']=@xen_data['memory_total_kib']
            @data['free_memory']=@xen_data['memory_free_kib']
        end

        def [](key)
            @data[key]
        end
    end
end

