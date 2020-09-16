# TA-windows-wec add-on for Splunk

This Add-on for Splunk ingests the output of the [wecutil](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/wecutil) command-line utility. Namely,

- Subscriptions list
- Subscription details and related event log statistics
- Subscription runtime status

## Subscriptions list

It retrieves the subscriptions from the output of the command:

```
wecutil es
```

## Subscription details and related event log statistics

Subscription details are a combination of the output of the command:

```
wecutil gs SUBSCRIPTION_NAME
```

And some statistics from the EventLog where the events are stored. From both, the following fields are present in the details:

- Subscription: Subscription Id.
- Enabled: True whether the subscription is enabled.
- ConfigurationMode: Custom, Normal, MinBandwidth, MinLatency.
- DeliveryMode: push, pull
- DeliveryMaxItems: Maximum number of items for batched delivery. Only valid for "custom" configuration mode.   
- DeliveryMaxLatencyTime: Delivery max latency time (milliseconds)
- HeartbeatInterval: Heartbeat interval (milliseconds)
- AllowedSourceDomainComputers: SDDL ACL that contains the allowed computers to participate in the subscription
- EventSource: list of computers (pairs: Address, Enabled) participating in the subscription
- LogName: Log name where the events are saved.
- EventPerSecond: Number of events per seconds (EPS).
- TotalEvents: Total number of events.
- NewestEventTime: Time stamp of the newest event in the log.
- OldestEventTime: Time stamp of the oldest event in the log.
- LogSize: Log size in Bytes.

**Note:** The list of event sources by default will not be included (see [event source splitting](#event-source-splitting)). As it would be the case of parsing the XML format. That is,

```
wecutil gs SUBSCRIPTION_NAME /f:XML
```

### References

- <https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/wecutil>
- <https://www.ibm.com/support/pages/qradar-how-measure-eps-rate-microsoft-windows-host>

## Subscription runtime status

It parses the output from the command:

```
wecutil gr SUBSCRIPTION_NAME
```

The following fields are created:

- Subscription : subscription name.
- RunTimeStatus : runtime status.
- LastError: last error value.
- ErrorMessage: Error message (**note:** only in case of error)
- ErrorTime: Timestamp of the error occurrence (**note:** only in case of error)
- EventSources : list of event sources (**note:** see [event source splitting](#event-source-splitting)). Each event source contains the following fields: 
    - ComputerName : event source computer name.
    - RunTimeStatus : runtime status.
    - LastError: last error value.
    - LastHeartbeatTime : Time stamp with the last check-in.

## Install the TA-wecutil add-on for Splunk

| Instance type | Supported | Required | Description
|---------------|-----------|----------|------------
| Search head   | No       | No      | Splunk App TBD.
| Indexer       | Yes       | No       | This add-on should be installed on a heavy forwarder present on the WEC server. There is no need to install this add-on on an indexer too.
| Universal forwarder | No       | No       | This add-on is not supported on a Universal Forwarder because it performs time formatting.
| Heavy forwarder     | Yes       | Yes       | Install this add-on on the heavy forwarder present on the WEC server.

That is, this add-on must be installed on the WEC server itself. It requires *wecsvc running, wecutil command-line utility and PowerShell v5 or newer.*

### Configuration and troubleshooting

The TA-windows-wec brings only two configuration items that are present in the configuration file *etc\default\ta-windows-wec_settings.conf*

#### Logging

```
    [logging]
    ; Log levels: DEBUG = Verbose, NONE = Default (Only warnings and errors)
    ; Errors and Warnings are also redirected to: splunk-powershell.ps1.log
    log_level=NONE   
```

The logs are generated to *var/log/splunk/splunk_ta-windows-wec.log* and therefore parsed by Splunk

```
index=_internal source=*ta-windows-wec*
```
**Note:** the log is overwritten when it reaches 15MB size

Said all that, you should check *splunk_ta-windows-wec.log and splunk-powershell.ps1.log*

#### Event source splitting

The list of event sources associated to a subscription can be enormous from just a few to thousands. This last makes the Splunk event very dense causing trouble to the browser to render the JSON array, think of arrays of thousands values for each event. But also, this can lead to easily reach the KV JSON event limit, and hence, truncate events. 

For those reasons two settings have been added:

- *rt_splitafter* indicates the number of event sources after which the Splunk event of the subscription runtime status will be splitted. By default is set to 70, that is, after 70 event sources, the Splunk event is splitted. Zero or negative value will not split the event sources, but may cause undesirable side effects when inspecting the Splunk events as aboved mentioned.
- *sd_splitafter* indicates the number of event sources after which the Splunk event will be splitted. By default is a negative value, that means no event sources are included in the Splunk event of the subscription details. A zero value will not split the event sources, but may cause undesirable side effects when inspecting the Splunk events as aboved mentioned.

```
    [eventsource]
    ; - Zero or negative integer value will not split the event sources. Warning! in case of having thousands of
    ;   event sources the browser may have problems rendering the events, but also you may reach the KV JSON char limit.
    ; - Positive integer value will split the event source into batches. 
    rt_splitafter=70
    ; - Negative integer value it will not include the event sources for the subscription details.
    ; - Zero value will include and will not split the event sources. Warning! in case of having thousands of
    ;   event sources the browser may have problems rendering the events, but also you may reach the KV JSON char limit.  
    ; - Positive integer value will split the event sources into batches. 
    sd_splitafter=-1
```

## References

- [Best practice for configuring EventLog forwarding in Windows Server 2016 and Windows Server 2012 R2](https://support.microsoft.com/en-us/help/4494356/best-practice-eventlog-forwarding-performance)
- [wecutil](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/wecutil)
- [Windows Event Forwarding for Network Defense](https://medium.com/palantir/windows-event-forwarding-for-network-defense-cb208d5ff86f)
- [Use Windows Event Forwarding to help with intrusion detection](https://docs.microsoft.com/en-us/windows/security/threat-protection/use-windows-event-forwarding-to-assist-in-intrusion-detection)
- [Develop apps and add-ons for Splunk Enterprise](https://dev.splunk.com/enterprise/docs/developapps)
- [Add-On Best Practice Check Tool](https://conf.splunk.com/session/2015/conf2015_JCoates-BWooden_Splunk_Community_Theatre_AddonBestPracticeCheck.pdf)
- [Splunk Add-on builder 2.2.0](https://docs.splunk.com/Documentation/AddonBuilder/2.2.0/UserGuide/UseTheApp)
- [Splunk Packaging Toolkit](https://dev.splunk.com/enterprise/docs/releaseapps/packagingtoolkit/installpkgtoolkit)

## TO DO List

- Create a Splunk App to exploit this information.