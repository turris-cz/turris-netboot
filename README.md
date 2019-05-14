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

Development
-----------

To deploy all the scripts directly into router you can simply run following script (might need to have you ssh-key deployed):

```bash
ROUTER_IP=192.168.1.1 ./dev-router-deploy.sh
```
