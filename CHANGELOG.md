# Changelog

## 0.4.1

### rename fields:

- orderdata ➜ orderitems  
- orderinfo ➜ ordervars   

exclude files in priv/

  
**add migration to upgrade tables:**

```
upgrade_local_order_record
defmodule MyApp.Repo.Migrations.UpgradeLocalOrderRecord do
  use Ecto.Migration

  def change do

    alter table(:orders) do
      add :archive, :json, default: "[]"
      add :history, :json, default: "[]"
      remove_if_exists :history, :map
    end

    rename table(:orders), :orderdata, to: :orderitems
    rename table(:orders), :orderinfo, to: :ordervars

  end
end
```


**extend schemas:**

```
    @derive {Inspect, except: [:archive,:history]}
  
    field :history, {:array, :map}
    field :archive, {:array, :map}
```

or for mysql:

```
    field :history, MyApp.MysqlTypes.JsonArray
    field :archive, MyApp.MysqlTypes.JsonArray
```
