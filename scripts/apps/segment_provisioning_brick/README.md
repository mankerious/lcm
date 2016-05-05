# Segment Provisioning Brick

This brick provides seamless client synchronization within domain or segment specified.

## Key Features:
From a high level perspective this brick can do for you

- Synchronize clients in domain specified
- Synchronize clients in segment specified

## Parameters

- `organization` or `domain` - Name of domain to be provisioned.

## Output

### Summary

After run brief summary will be displayed.

```
+---------+-------+
|     Summary     |
+---------+-------+
| status  | count |
+---------+-------+
| CREATED | 5     |
+---------+-------+
```

### Errors

In case of errors table similar to this will be displayed.

```
+----------+--------------------------+
|               Errors                |
+----------+--------------------------+
| client   | reason                   |
+----------+--------------------------+
| client-5 | Master release not found |
| client-4 | Master release not found |
| client-3 | Master release not found |
| client-2 | Master release not found |
| client-1 | Master release not found |
+----------+--------------------------+
```