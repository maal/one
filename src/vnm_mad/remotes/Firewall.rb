# -------------------------------------------------------------------------- #
# Copyright 2002-2012, OpenNebula Project Leads (OpenNebula.org)             #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

class OpenNebulaFirewall < OpenNebulaNetwork
    XPATH_FILTER =  "TEMPLATE/NIC[ICMP|WHITE_PORTS_TCP|WHITE_PORTS_UDP|" <<
                    "BLACK_PORTS_TCP|BLACK_PORTS_UDP|NO_IP_SPOOFING]"

    def initialize(vm, deploy_id = nil, hypervisor = nil)
        super(vm,XPATH_FILTER,deploy_id,hypervisor)
    end

    def activate
        vm_id =  @vm['ID']
        process do |nic|
            #:white_ports_tcp => iptables_range
            #:white_ports_udp => iptables_range
            #:black_ports_tcp => iptables_range
            #:black_ports_udp => iptables_range
            #:icmp            => 'DROP' or 'NO'
            #:no_ip_spoofing  => 'YES' or 'NO'

            nic_rules_in  = Array.new
            nic_rules_out = Array.new

            chain_in  = "one-#{vm_id}-#{nic[:network_id]}-in"
            chain_out = "one-#{vm_id}-#{nic[:network_id]}-out"

            tap = nic[:tap]

             if tap
                #NO_IP_SPOOFING
                if nic[:no_ip_spoofing] and nic[:no_ip_spoofing].match(/y(es)?/i)
                    nic_rules_in << filter_noipspoofing(chain_in, nic[:ip], :in)
                    nic_rules_out << filter_noipspoofing(chain_out, nic[:ip], :out)
                end

                #TCP
                if range = nic[:white_ports_tcp]
                    nic_rules_out << filter_established(chain_out, :tcp, :accept)
                    nic_rules_out << filter_ports(chain_out, :tcp, range, :accept)
                    nic_rules_out << filter_protocol(chain_out, :tcp, :drop)
                elsif range = nic[:black_ports_tcp]
                    nic_rules_out << filter_ports(chain_out, :tcp, range, :drop)
                end

                #UDP
                if range = nic[:white_ports_udp]
                    nic_rules_out << filter_established(chain_out, :udp, :accept)
                    nic_rules_out << filter_ports(chain_out, :udp, range, :accept)
                    nic_rules_out << filter_protocol(chain_out, :udp, :drop)
                elsif range = nic[:black_ports_udp]
                    nic_rules_out << filter_ports(chain_out, :udp, range, :drop)
                end

                #ICMP
                if nic[:icmp]
                    if %w(no drop).include? nic[:icmp].downcase
                        nic_rules_out << filter_established(chain_out, :icmp, :accept)
                        nic_rules_out << filter_protocol(chain_out, :icmp, :drop)
                    end
                end

                process_chain(chain_out, tap, nic_rules_out, :out)
                process_chain(chain_in, tap, nic_rules_in, :in)
            end
        end
    end

    def deactivate
        vm_id =  @vm['ID']
        process do |nic|
            chain_in    = "one-#{vm_id}-#{nic[:network_id]}-in"
            chain_out   = "one-#{vm_id}-#{nic[:network_id]}-out"
            [chain_in, chain_out].each do |chain|
                cmd = "#{COMMANDS[:iptables]} -n -v --line-numbers -L FORWARD"
                iptables_out = `#{cmd}`
                if m = iptables_out.match(/.*#{chain}.*/)
                    rule_num = m[0].split(/\s+/)[0]
                    purge_chain(chain, rule_num)
                end
            end
        end
    end

    def purge_chain(chain, rule_num)
        rules = Array.new
        rules << rule("-D FORWARD #{rule_num}")
        rules << rule("-F #{chain}")
        rules << rule("-X #{chain}")
        run_rules rules
    end

    def process_chain(chain, tap, nic_rules, sense)
        rules = Array.new
        if !nic_rules.empty?
            # new chain
            rules << new_chain(chain)
            # move tap traffic to chain
            rules << tap_to_chain(tap, chain, sense)

            rules << nic_rules
        end
        run_rules rules
    end

    def filter_noipspoofing(chain, ip, sense)
        if sense == :in
            param = "-s"
        else
            param = "-d"
        end

        rule "-A #{chain} ! #{param} #{ip} -j DROP"
    end

    def filter_established(chain, protocol, policy)
        policy   = policy.to_s.upcase
        rule "-A #{chain} -p #{protocol} -m state --state ESTABLISHED -j #{policy}"
    end

    def run_rules(rules)
        rules.flatten.each do |rule|
            OpenNebula.exec_and_log(rule)
        end
    end

    def range?(range)
        range.match(/^(?:(?:\d+|\d+:\d+),)*(?:\d+|\d+:\d+)$/)
    end

    def filter_protocol(chain, protocol, policy)
        policy   = policy.to_s.upcase
        rule "-A #{chain} -p #{protocol} -j #{policy}"
    end

    def filter_ports(chain, protocol, range, policy)
        policy   = policy.to_s.upcase
        range.gsub!(/\s+/,"")

        if range? range
           rule "-A #{chain} -p #{protocol} -m multiport --dports #{range} -j #{policy}"
        end
    end

    def tap_to_chain(tap, chain, sense)
        rule "-A FORWARD -m physdev --physdev-#{sense.to_s} #{tap} -j #{chain}"
    end

    def new_chain(chain)
        rule "-N #{chain}"
    end

    def rule(rule)
        "#{COMMANDS[:iptables]} #{rule}"
    end
end
