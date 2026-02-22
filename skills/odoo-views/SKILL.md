---
name: odoo-views
description: Odoo views and frontend — form/tree/kanban/search/graph/pivot/calendar XML views, QWeb reports, OWL components, wizards, view inheritance
---

# Odoo Views & Frontend

Staff-engineer-level Odoo 17/18 view patterns. Covers form views with statusbar and chatter, tree/list views with decorations, kanban views with progressbar, search views with faceted search, graph/pivot/calendar views, QWeb PDF reports, OWL framework components, wizards (simple and multi-step), and view inheritance.

## Table of Contents

1. [Form View](#form-view)
2. [Tree/List View](#treelist-view)
3. [Kanban View](#kanban-view)
4. [Search View](#search-view)
5. [Graph, Pivot, Calendar Views](#graph-pivot-calendar-views)
6. [QWeb Reports](#qweb-reports)
7. [OWL Components](#owl-components)
8. [Wizards](#wizards)
9. [View Inheritance](#view-inheritance)
10. [Best Practices](#best-practices)
11. [Anti-Patterns](#anti-patterns)

---

## Form View

```xml
<record id="my_model_form" model="ir.ui.view">
    <field name="name">my.model.form</field>
    <field name="model">my.model</field>
    <field name="arch" type="xml">
        <form string="My Model">
            <!-- Header with buttons and statusbar -->
            <header>
                <button name="action_submit" type="object" string="Submit"
                        class="btn-primary"
                        invisible="state != 'draft'"
                        confirm="Are you sure?"/>

                <button name="action_approve" type="object" string="Approve"
                        class="btn-success"
                        invisible="state != 'submitted'"
                        groups="my_module.group_my_module_manager"/>

                <field name="state" widget="statusbar"
                       statusbar_visible="draft,submitted,approved,done"/>
            </header>

            <!-- Ribbon for archived records -->
            <widget name="web_ribbon" title="Archived" bg_color="text-bg-danger"
                    invisible="active"/>

            <sheet>
                <!-- Title area -->
                <div class="oe_title">
                    <h1>
                        <field name="name" placeholder="Record Name..."/>
                    </h1>
                    <div>
                        <field name="tag_ids" widget="many2many_tags"
                               options="{'color_field': 'color'}"/>
                    </div>
                </div>

                <!-- Main content in groups -->
                <group>
                    <group>
                        <field name="partner_id"
                               options="{'no_create': True, 'no_open': True}"/>
                        <field name="company_id" groups="base.group_multi_company"/>
                    </group>
                    <group>
                        <field name="date_start"/>
                        <field name="amount" widget="monetary"
                               options="{'currency_field': 'currency_id'}"/>
                        <field name="currency_id" invisible="1"/>
                    </group>
                </group>

                <!-- Notebook with pages -->
                <notebook>
                    <page string="Lines" name="lines">
                        <field name="line_ids">
                            <tree editable="bottom">
                                <field name="sequence" widget="handle"/>
                                <field name="product_id"/>
                                <field name="quantity"/>
                                <field name="price_unit"/>
                                <field name="subtotal" sum="Total"/>
                            </tree>
                        </field>
                        <group class="oe_subtotal_footer">
                            <field name="total_amount" widget="monetary"/>
                        </group>
                    </page>
                    <page string="Other Info" name="other">
                        <group>
                            <field name="note" widget="html"/>
                        </group>
                    </page>
                </notebook>
            </sheet>

            <!-- Chatter -->
            <div class="oe_chatter">
                <field name="message_follower_ids" groups="base.group_user"/>
                <field name="activity_ids"/>
                <field name="message_ids"/>
            </div>
        </form>
    </field>
</record>
```

---

## Tree/List View

```xml
<record id="my_model_tree" model="ir.ui.view">
    <field name="name">my.model.tree</field>
    <field name="model">my.model</field>
    <field name="arch" type="xml">
        <tree string="My Models"
              multi_edit="1"
              sample="1"
              decoration-info="state == 'draft'"
              decoration-success="state == 'approved'"
              decoration-danger="state == 'rejected'">

            <!-- Multi-action buttons -->
            <header>
                <button name="action_bulk_approve" type="object" string="Approve"/>
            </header>

            <field name="sequence" widget="handle"/>
            <field name="name"/>
            <field name="partner_id"/>
            <field name="state" widget="badge"/>
            <field name="amount" sum="Total" widget="monetary"/>
            <field name="currency_id" column_invisible="1"/>
            <field name="create_date" optional="hide"/>
            <field name="activity_ids" widget="list_activity"/>
        </tree>
    </field>
</record>
```

---

## Kanban View

```xml
<record id="my_model_kanban" model="ir.ui.view">
    <field name="name">my.model.kanban</field>
    <field name="model">my.model</field>
    <field name="arch" type="xml">
        <kanban default_group_by="state"
                quick_create="false"
                sample="1"
                class="o_kanban_small_column">

            <field name="id"/>
            <field name="name"/>
            <field name="partner_id"/>
            <field name="amount"/>
            <field name="state"/>
            <field name="color"/>
            <field name="activity_state"/>

            <progressbar field="activity_state"
                        colors='{"planned": "success", "today": "warning", "overdue": "danger"}'/>

            <templates>
                <t t-name="kanban-box">
                    <div t-attf-class="oe_kanban_color_#{kanban_getcolor(record.color.raw_value)} oe_kanban_global_click">
                        <div class="oe_kanban_content">
                            <div class="o_dropdown_kanban dropdown">
                                <a class="dropdown-toggle o-no-caret btn" role="button"
                                   data-bs-toggle="dropdown" href="#">
                                    <span class="fa fa-ellipsis-v"/>
                                </a>
                                <div class="dropdown-menu" role="menu">
                                    <a t-if="widget.editable" role="menuitem"
                                       type="edit" class="dropdown-item">Edit</a>
                                    <a t-if="widget.deletable" role="menuitem"
                                       type="delete" class="dropdown-item">Delete</a>
                                    <ul class="oe_kanban_colorpicker" data-field="color"/>
                                </div>
                            </div>

                            <div class="oe_kanban_details">
                                <strong><field name="name"/></strong>
                                <div><field name="partner_id"/></div>
                                <div><field name="amount" widget="monetary"/></div>
                            </div>

                            <div class="oe_kanban_footer">
                                <div class="o_kanban_record_bottom">
                                    <div class="oe_kanban_bottom_left">
                                        <field name="activity_ids" widget="kanban_activity"/>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </t>
            </templates>
        </kanban>
    </field>
</record>
```

---

## Search View

```xml
<record id="my_model_search" model="ir.ui.view">
    <field name="name">my.model.search</field>
    <field name="model">my.model</field>
    <field name="arch" type="xml">
        <search string="Search My Model">
            <!-- Search fields -->
            <field name="name" string="Name or Reference"
                   filter_domain="['|', ('name', 'ilike', self), ('reference', 'ilike', self)]"/>
            <field name="partner_id"/>

            <!-- Filters -->
            <filter string="Draft" name="draft" domain="[('state', '=', 'draft')]"/>
            <filter string="Approved" name="approved" domain="[('state', '=', 'approved')]"/>
            <separator/>
            <filter string="My Records" name="my_records"
                    domain="[('create_uid', '=', uid)]"/>
            <filter string="Archived" name="archived"
                    domain="[('active', '=', False)]"/>

            <!-- Group By -->
            <group expand="0" string="Group By">
                <filter string="Partner" name="group_partner"
                        context="{'group_by': 'partner_id'}"/>
                <filter string="State" name="group_state"
                        context="{'group_by': 'state'}"/>
                <filter string="Creation Date" name="group_create_date"
                        context="{'group_by': 'create_date:month'}"/>
            </group>

            <!-- Searchpanel (faceted search) -->
            <searchpanel>
                <field name="state" icon="fa-filter" select="multi" enable_counters="1"/>
                <field name="partner_id" icon="fa-users" select="multi" enable_counters="1"/>
            </searchpanel>
        </search>
    </field>
</record>
```

---

## Graph, Pivot, Calendar Views

```xml
<!-- Graph View -->
<record id="my_model_graph" model="ir.ui.view">
    <field name="name">my.model.graph</field>
    <field name="model">my.model</field>
    <field name="arch" type="xml">
        <graph string="Sales Analysis" type="bar" sample="1">
            <field name="partner_id" type="row"/>
            <field name="amount" type="measure"/>
        </graph>
    </field>
</record>

<!-- Pivot View -->
<record id="my_model_pivot" model="ir.ui.view">
    <field name="name">my.model.pivot</field>
    <field name="model">my.model</field>
    <field name="arch" type="xml">
        <pivot string="Sales Pivot" sample="1">
            <field name="partner_id" type="row"/>
            <field name="create_date" interval="month" type="col"/>
            <field name="amount" type="measure"/>
        </pivot>
    </field>
</record>

<!-- Calendar View -->
<record id="my_model_calendar" model="ir.ui.view">
    <field name="name">my.model.calendar</field>
    <field name="model">my.model</field>
    <field name="arch" type="xml">
        <calendar string="Calendar"
                  date_start="date_start"
                  date_stop="date_end"
                  color="partner_id"
                  mode="month"
                  event_open_popup="true">
            <field name="name"/>
            <field name="partner_id"/>
        </calendar>
    </field>
</record>
```

---

## QWeb Reports

### Report Declaration and Template

```xml
<!-- Report action -->
<record id="action_report_my_model" model="ir.actions.report">
    <field name="name">My Model Report</field>
    <field name="model">my.model</field>
    <field name="report_type">qweb-pdf</field>
    <field name="report_name">my_module.report_my_model_document</field>
    <field name="binding_model_id" ref="model_my_model"/>
    <field name="binding_type">report</field>
</record>

<!-- Report template -->
<template id="report_my_model_document">
    <t t-call="web.html_container">
        <t t-foreach="docs" t-as="doc">
            <t t-call="web.external_layout">
                <div class="page">
                    <div class="row">
                        <div class="col-6">
                            <h2><span t-field="doc.name"/></h2>
                        </div>
                        <div class="col-6 text-end">
                            <strong>Date:</strong>
                            <span t-field="doc.create_date"
                                  t-options="{'widget': 'date'}"/>
                        </div>
                    </div>

                    <!-- Lines table -->
                    <table class="table table-sm">
                        <thead>
                            <tr>
                                <th>Product</th>
                                <th class="text-end">Quantity</th>
                                <th class="text-end">Subtotal</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr t-foreach="doc.line_ids" t-as="line">
                                <td><span t-field="line.product_id.name"/></td>
                                <td class="text-end"><span t-field="line.quantity"/></td>
                                <td class="text-end">
                                    <span t-field="line.subtotal"
                                          t-options="{'widget': 'monetary', 'display_currency': doc.currency_id}"/>
                                </td>
                            </tr>
                        </tbody>
                    </table>

                    <!-- Total -->
                    <div class="row">
                        <div class="col-6 offset-6">
                            <table class="table table-sm">
                                <tr>
                                    <td><strong>Total:</strong></td>
                                    <td class="text-end">
                                        <span t-field="doc.total_amount"
                                              t-options="{'widget': 'monetary', 'display_currency': doc.currency_id}"/>
                                    </td>
                                </tr>
                            </table>
                        </div>
                    </div>
                </div>
            </t>
        </t>
    </t>
</template>
```

### Report Controller (Python Preprocessing)

```python
from odoo import models

class ReportMyModel(models.AbstractModel):
    _name = 'report.my_module.report_my_model_document'
    _description = 'My Model Report'

    def _get_report_values(self, docids, data=None):
        """
        Staff pattern: Preprocess data for report.
        Compute totals, groupings, etc. in Python instead of QWeb.
        """
        docs = self.env['my.model'].browse(docids)
        summary = {
            'total': sum(doc.total_amount for doc in docs),
            'count': len(docs),
        }
        return {
            'doc_ids': docids,
            'doc_model': 'my.model',
            'docs': docs,
            'summary': summary,
        }
```

---

## OWL Components

### Component with Services and Reactive State

```javascript
/** @odoo-module **/

import { Component, useState, onWillStart, onMounted } from "@odoo/owl";
import { useService } from "@web/core/utils/hooks";
import { registry } from "@web/core/registry";

export class MyComponent extends Component {
    static template = "my_module.MyComponent";
    static props = {
        recordId: Number,
        optional: { type: String, optional: true },
    };

    setup() {
        this.orm = useService("orm");
        this.action = useService("action");
        this.notification = useService("notification");

        this.state = useState({
            count: 0,
            data: null,
            loading: false,
        });

        onWillStart(async () => {
            await this.loadData();
        });
    }

    async loadData() {
        this.state.loading = true;
        try {
            this.state.data = await this.orm.read(
                "my.model",
                [this.props.recordId],
                ["name", "amount"]
            );
        } catch (error) {
            this.notification.add("Failed to load data", { type: "danger" });
        } finally {
            this.state.loading = false;
        }
    }

    async onSave() {
        await this.orm.write("my.model", [this.props.recordId], {
            amount: this.state.data.amount,
        });
        this.notification.add("Saved successfully", { type: "success" });
    }
}

registry.category("actions").add("my_module.my_component", MyComponent);
```

### OWL Template

```xml
<?xml version="1.0" encoding="UTF-8"?>
<templates xml:space="preserve">
    <t t-name="my_module.MyComponent">
        <div class="my-component">
            <div t-if="state.loading" class="spinner-border">Loading...</div>
            <div t-else="">
                <h3 t-esc="state.data?.name"/>
                <input type="number" t-model="state.data.amount" class="form-control"/>
                <button class="btn btn-primary" t-on-click="onSave">Save</button>
            </div>
        </div>
    </t>
</templates>
```

---

## Wizards

### Simple Wizard

```python
class MyWizard(models.TransientModel):
    _name = 'my.wizard'
    _description = 'My Wizard'

    partner_id = fields.Many2one('res.partner', required=True)
    date_from = fields.Date(required=True)
    date_to = fields.Date(required=True)

    @api.constrains('date_from', 'date_to')
    def _check_dates(self):
        for wizard in self:
            if wizard.date_to < wizard.date_from:
                raise UserError(_('End date must be after start date.'))

    def action_confirm(self):
        self.ensure_one()
        active_ids = self.env.context.get('active_ids', [])
        records = self.env['my.model'].browse(active_ids)

        records.write({
            'partner_id': self.partner_id.id,
            'date_from': self.date_from,
        })

        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {
                'title': _('Success'),
                'message': _('%s records updated.') % len(records),
                'type': 'success',
            }
        }
```

### Wizard View and Action

```xml
<record id="my_wizard_form" model="ir.ui.view">
    <field name="name">my.wizard.form</field>
    <field name="model">my.wizard</field>
    <field name="arch" type="xml">
        <form string="My Wizard">
            <group>
                <field name="partner_id"/>
                <field name="date_from"/>
                <field name="date_to"/>
            </group>
            <footer>
                <button string="Confirm" name="action_confirm"
                        type="object" class="btn-primary"/>
                <button string="Cancel" special="cancel"/>
            </footer>
        </form>
    </field>
</record>

<record id="action_my_wizard" model="ir.actions.act_window">
    <field name="name">My Wizard</field>
    <field name="res_model">my.wizard</field>
    <field name="view_mode">form</field>
    <field name="target">new</field>
    <field name="binding_model_id" ref="model_my_model"/>
</record>
```

---

## View Inheritance

```xml
<record id="res_partner_form_inherit" model="ir.ui.view">
    <field name="name">res.partner.form.inherit</field>
    <field name="model">res.partner</field>
    <field name="inherit_id" ref="base.view_partner_form"/>
    <field name="arch" type="xml">
        <!-- Add field after existing field -->
        <field name="phone" position="after">
            <field name="custom_field"/>
        </field>

        <!-- Add page to notebook -->
        <xpath expr="//notebook" position="inside">
            <page string="Custom Info">
                <group>
                    <field name="is_vip"/>
                </group>
            </page>
        </xpath>

        <!-- Replace element -->
        <field name="website" position="replace">
            <field name="website" widget="url"/>
        </field>

        <!-- Add attributes -->
        <field name="email" position="attributes">
            <attribute name="required">1</attribute>
        </field>
    </field>
</record>
```

---

## Best Practices

1. **Use statusbar widget** for state fields in form headers
2. **Enable multi_edit** on tree views for bulk editing
3. **Use decorations** for visual state indicators in tree views
4. **Searchpanel for faceted search** - Enable counters for better UX
5. **Preprocess report data in Python** - Keep QWeb templates simple
6. **OWL useState for reactivity** - Automatic re-render on state change
7. **Use services in OWL** - `orm`, `action`, `notification` via `useService`
8. **Wizard context** - Pass `active_ids` from context for bulk operations
9. **View inheritance positions** - `after`, `before`, `inside`, `replace`, `attributes`
10. **Calendar color** - Use relational field for color to group visually

---

## Anti-Patterns

- Complex business logic in QWeb templates (preprocess in Python)
- Missing `invisible` conditions on buttons (show all buttons in all states)
- Not using `groups` attribute for role-based field visibility
- Wizard without `ensure_one()` before processing
- Heavy computation in OWL `setup()` (use `onWillStart` with async)
- Not using `widget="handle"` for drag-to-reorder in tree views
- Missing `binding_model_id` on wizard actions (wizard not accessible)

---

## Sources & References

- [Views - Odoo 16](https://www.odoo.com/documentation/16.0/developer/reference/backend/views.html)
- [QWeb Reports - Odoo 18](https://www.odoo.com/documentation/18.0/developer/reference/backend/reports.html)
- [Custom Paper Format in QWeb Reports](https://www.iwesabe.com/blog/how-to-use-custom-paper-format-in-odoo-qweb-reports)
- [Odoo 17/18 OWL Framework Best Practices](https://www.odoo.com/event/odoo-community-days-india-4312/track/best-development-practices-for-enhanced-efficiency-in-odoos-owl-framework-5604)
- [Odoo 18 OWL JS Key Improvements](https://pysquad.com/blogs/odoo-18-owl-js-key-improvements-over-odoo-17)
- [OWL Components - Odoo 18](https://www.odoo.com/documentation/18.0/developer/tutorials/discover_js_framework/01_owl_components.html)
- [Odoo Wizards Complete Guide](https://medium.com/@aymenfarhani28/odoo-wizards-the-complete-guide-9e453e8c282a)
- [Inheritance - Odoo 18](https://www.odoo.com/documentation/18.0/developer/tutorials/server_framework_101/12_inheritance.html)
