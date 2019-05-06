Netboot Workflow
----------------


|OMNIA (root)    |           | OMNIA (turris-netboot)    |               |  MOX (AP) |
|:--------------:|:---------:|:-------------------------:|:-------------:|:---------:|
|                |           | image                     | >>            | rescue.sh |
|                |           |                           |               | rescue.sh |
|                |           | manage.sh register        | << `pair`     | rescue.sh |
|                |           | `my_ssh_key.pub` ???      |               |           |
| manage.sh      | >> list   |                           |               |           |
| manage.sh      | >> accept | `my_ssh_key.pub` OK       |               |           |
|                |           | server.sh                 | << `status`   | rescue.sh |
|                |           | server.sh                 | << `get_root` | rescue.sh |
|                |           | ...                       | ...           | ...       |
|                |           |                           |               | chroot    |
