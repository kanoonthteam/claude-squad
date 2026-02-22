---
name: odoo-backend
description: Odoo backend patterns — security (access rights, record rules, field-level), inheritance (_inherit, _inherits, abstract, mixin), automated actions, cron jobs, API controllers, multi-company, workflows
---

# Odoo Backend & Security Patterns

Staff-engineer-level Odoo 17/18 backend patterns. Covers security architecture (access rights, record rules, field-level security), inheritance patterns (_inherit, _inherits, abstract, mixin), automated actions and cron jobs, API controllers (JSON and HTTP), multi-company and multi-currency, workflow state machines, and module dependencies.

## Table of Contents

1. [Security Architecture](#security-architecture)
2. [Inheritance Patterns](#inheritance-patterns)
3. [Automated Actions & Cron](#automated-actions--cron)
4. [API Controllers](#api-controllers)
5. [Multi-Company & Multi-Currency](#multi-company--multi-currency)
6. [Workflow State Machine](#workflow-state-machine)
7. [Migration Scripts](#migration-scripts)
8. [Best Practices](#best-practices)
9. [Anti-Patterns](#anti-patterns)

---

## Security Architecture

### Access Rights (ir.model.access)

```csv
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_my_model_user,my.model.user,model_my_model,base.group_user,1,1,1,0
access_my_model_manager,my.model.manager,model_my_model,group_my_module_manager,1,1,1,1
access_my_model_public,my.model.public,model_my_model,,1,0,0,0
```

**Principles:**
- Access rights are **additive** - user gets all permissions from all groups
- Default to **stronger security** - users can relax if needed
- Public access (no group) should be read-only

### Security Groups

```xml
<odoo>
    <data>
        <record id="module_category_my_module" model="ir.module.category">
            <field name="name">My Module</field>
            <field name="sequence">30</field>
        </record>

        <!-- User Group -->
        <record id="group_my_module_user" model="res.groups">
            <field name="name">User</field>
            <field name="category_id" ref="module_category_my_module"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
        </record>

        <!-- Manager Group (inherits User) -->
        <record id="group_my_module_manager" model="res.groups">
            <field name="name">Manager</field>
            <field name="category_id" ref="module_category_my_module"/>
            <field name="implied_ids" eval="[(4, ref('group_my_module_user'))]"/>
        </record>
    </data>
</odoo>
```

### Record Rules

```xml
<odoo>
    <data noupdate="1">
        <!-- User can only see own records -->
        <record id="my_model_rule_own" model="ir.rule">
            <field name="name">My Model: User Own Records</field>
            <field name="model_id" ref="model_my_model"/>
            <field name="domain_force">[('create_uid', '=', user.id)]</field>
            <field name="groups" eval="[(4, ref('group_my_module_user'))]"/>
        </record>

        <!-- Manager can see all records -->
        <record id="my_model_rule_all" model="ir.rule">
            <field name="name">My Model: Manager All Records</field>
            <field name="model_id" ref="model_my_model"/>
            <field name="domain_force">[(1, '=', 1)]</field>
            <field name="groups" eval="[(4, ref('group_my_module_manager'))]"/>
        </record>

        <!-- Multi-company rule (global) -->
        <record id="my_model_rule_company" model="ir.rule">
            <field name="name">My Model: Multi-company</field>
            <field name="model_id" ref="model_my_model"/>
            <field name="domain_force">
                ['|',
                    ('company_id', '=', False),
                    ('company_id', 'in', company_ids)
                ]
            </field>
            <field name="global" eval="True"/>
        </record>
    </data>
</odoo>
```

### Field-Level Security and Best Practices

```python
class SecureModel(models.Model):
    _name = 'secure.model'

    # Visible only to managers
    secret_field = fields.Char(
        groups='my_module.group_my_module_manager'
    )

    def secure_operation(self):
        """Staff pattern: Always check permissions explicitly."""
        self.check_access_rights('write')
        self.check_access_rule('write')
        self.write({'field': 'value'})

    def bypass_security_carefully(self):
        """
        Staff pattern: Use sudo() only when absolutely necessary.
        Document why sudo is needed.
        """
        # Bypass security to update system configuration
        config = self.env['ir.config_parameter'].sudo()
        config.set_param('my_module.setting', 'value')
```

---

## Inheritance Patterns

### Classical Inheritance (_inherit)

```python
class PartnerExtension(models.Model):
    """Extend existing model with new fields/methods."""
    _inherit = 'res.partner'

    custom_field = fields.Char()
    is_vip = fields.Boolean(default=False)

    def write(self, vals):
        """Add logging when partner is updated."""
        result = super().write(vals)
        if 'is_vip' in vals:
            self.message_post(body=_('VIP status changed.'))
        return result
```

### Delegation Inheritance (_inherits)

```python
class ProductTemplate(models.Model):
    """Delegate fields to another model."""
    _name = 'product.template'
    _inherits = {'product.product': 'product_variant_id'}

    product_variant_id = fields.Many2one(
        'product.product',
        'Product Variant',
        required=True,
        ondelete='cascade',
    )
    # Can access product.product fields directly
```

### Abstract Model (Prototype Inheritance)

```python
class AbstractCommon(models.AbstractModel):
    """Reusable fields/methods. Not stored in database."""
    _name = 'abstract.common'
    _description = 'Abstract Common Fields'

    name = fields.Char(required=True, index=True)
    active = fields.Boolean(default=True)
    sequence = fields.Integer(default=10)

    _sql_constraints = [
        ('name_unique', 'UNIQUE(name)', 'Name must be unique')
    ]

    def action_archive(self):
        self.write({'active': False})


class ConcreteModel(models.Model):
    _name = 'concrete.model'
    _inherit = 'abstract.common'  # Get all fields/methods
    amount = fields.Float()
```

### Mixin Pattern

```python
class ImageMixin(models.AbstractModel):
    """Mixin for image handling."""
    _name = 'image.mixin'
    _description = 'Image Mixin'

    image_1920 = fields.Image(max_width=1920, max_height=1920)
    image_1024 = fields.Image(
        compute='_compute_image_1024', store=True,
    )

    @api.depends('image_1920')
    def _compute_image_1024(self):
        for record in self:
            record.image_1024 = tools.image_resize_image(
                record.image_1920, size=(1024, 1024)
            )


class MyModelWithImage(models.Model):
    _name = 'my.model.image'
    _inherit = ['my.model', 'image.mixin']  # Multiple inheritance
```

---

## Automated Actions & Cron

### Scheduled Actions (Cron)

```python
class CronExample(models.Model):
    _name = 'cron.example'

    @api.model
    def cron_cleanup_old_records(self):
        """Process in batches, commit per batch."""
        cutoff_date = fields.Date.today() - timedelta(days=90)
        batch_size = 500

        while True:
            records = self.search([
                ('create_date', '<', cutoff_date),
                ('active', '=', False),
            ], limit=batch_size)

            if not records:
                break

            _logger.info(f'Deleting {len(records)} old records')
            records.unlink()
            self.env.cr.commit()
```

```xml
<record id="ir_cron_cleanup_old_records" model="ir.cron">
    <field name="name">Cleanup Old Records</field>
    <field name="model_id" ref="model_cron_example"/>
    <field name="state">code</field>
    <field name="code">model.cron_cleanup_old_records()</field>
    <field name="interval_number">1</field>
    <field name="interval_type">days</field>
    <field name="numbercall">-1</field>
    <field name="active" eval="True"/>
</record>
```

### Server Actions and Automated Actions

```xml
<!-- Server action: Python code -->
<record id="action_server_mark_vip" model="ir.actions.server">
    <field name="name">Mark as VIP</field>
    <field name="model_id" ref="base.model_res_partner"/>
    <field name="binding_model_id" ref="base.model_res_partner"/>
    <field name="binding_view_types">list,form</field>
    <field name="state">code</field>
    <field name="code">records.write({'is_vip': True})</field>
</record>

<!-- Automated action: trigger on state change -->
<record id="auto_action_send_email_on_approve" model="base.automation">
    <field name="name">Send Email on Approval</field>
    <field name="model_id" ref="model_my_model"/>
    <field name="trigger">on_write</field>
    <field name="filter_domain">[('state', '=', 'approved')]</field>
    <field name="filter_pre_domain">[('state', '!=', 'approved')]</field>
    <field name="state">email</field>
    <field name="template_id" ref="email_template_approval_notification"/>
</record>
```

---

## API Controllers

```python
from odoo import http
from odoo.http import request
import json

class MyAPIController(http.Controller):

    @http.route('/api/my_model', type='json', auth='user', methods=['GET'])
    def get_records(self, **kwargs):
        """JSON API endpoint."""
        domain = kwargs.get('domain', [])
        fields = kwargs.get('fields', ['id', 'name'])
        records = request.env['my.model'].search_read(domain, fields)
        return {'success': True, 'data': records}

    @http.route('/api/my_model/<int:record_id>', type='http', auth='public',
                methods=['GET'], csrf=False)
    def get_record_http(self, record_id, **kwargs):
        """HTTP endpoint (public access)."""
        record = request.env['my.model'].sudo().browse(record_id)

        if not record.exists():
            return request.make_response(
                json.dumps({'error': 'Not found'}),
                headers={'Content-Type': 'application/json'},
                status=404,
            )

        data = {'id': record.id, 'name': record.name}
        return request.make_response(
            json.dumps(data),
            headers={'Content-Type': 'application/json'},
        )

    @http.route('/api/my_model', type='json', auth='user', methods=['POST'])
    def create_record(self, **kwargs):
        """Create record via API."""
        try:
            record = request.env['my.model'].create(kwargs)
            return {'success': True, 'id': record.id}
        except Exception as e:
            return {'success': False, 'error': str(e)}
```

---

## Multi-Company & Multi-Currency

### Multi-Company Model

```python
class MultiCompanyModel(models.Model):
    _name = 'multi.company.model'
    _check_company_auto = True  # Enable automatic company checks

    name = fields.Char(required=True)

    company_id = fields.Many2one(
        'res.company', required=True,
        default=lambda self: self.env.company, index=True,
    )

    partner_id = fields.Many2one(
        'res.partner',
        check_company=True,  # Validate same company
    )

    _sql_constraints = [
        ('name_company_unique', 'UNIQUE(name, company_id)',
         'Name must be unique per company'),
    ]
```

### Multi-Currency

```python
class MultiCurrencyModel(models.Model):
    _name = 'multi.currency.model'

    currency_id = fields.Many2one(
        'res.currency', required=True,
        default=lambda self: self.env.company.currency_id,
    )

    amount = fields.Monetary(currency_field='currency_id')

    amount_company_currency = fields.Monetary(
        currency_field='company_currency_id',
        compute='_compute_amount_company_currency',
        store=True,
    )

    company_currency_id = fields.Many2one(
        'res.currency', related='company_id.currency_id', store=True,
    )

    @api.depends('amount', 'currency_id', 'company_id')
    def _compute_amount_company_currency(self):
        for record in self:
            record.amount_company_currency = record.currency_id._convert(
                record.amount,
                record.company_currency_id,
                record.company_id,
                fields.Date.today(),
            )
```

---

## Workflow State Machine

```python
class WorkflowModel(models.Model):
    _name = 'workflow.model'
    _inherit = ['mail.thread', 'mail.activity.mixin']

    state = fields.Selection([
        ('draft', 'Draft'),
        ('submitted', 'Submitted'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
        ('done', 'Done'),
        ('cancelled', 'Cancelled'),
    ], default='draft', required=True, tracking=True)

    approver_id = fields.Many2one('res.users', tracking=True)
    approval_date = fields.Datetime(tracking=True)

    def action_submit(self):
        self._validate_transition('submitted')
        self.write({'state': 'submitted'})
        self.message_post(body='Record submitted for review', message_type='notification')

    def action_approve(self):
        self._validate_transition('approved')
        self.write({
            'state': 'approved',
            'approval_date': fields.Datetime.now(),
            'approver_id': self.env.user.id,
        })

    def action_cancel(self):
        self.write({'state': 'cancelled'})

    def action_reset_to_draft(self):
        self._validate_transition('draft')
        self.write({
            'state': 'draft',
            'approver_id': False,
            'approval_date': False,
        })

    def _validate_transition(self, new_state):
        allowed = {
            'draft': ['submitted'],
            'submitted': ['approved', 'rejected', 'cancelled'],
            'approved': ['done', 'cancelled'],
            'rejected': ['draft'],
            'cancelled': ['draft'],
        }
        for record in self:
            if new_state not in allowed.get(record.state, []):
                raise UserError(_(
                    'Cannot transition from %(from)s to %(to)s',
                    from_=record.state, to=new_state,
                ))
```

---

## Migration Scripts

### Pre-Migration (before module update)

```python
# migrations/18.0.1.0.1/pre-migrate.py
import logging
_logger = logging.getLogger(__name__)

def migrate(cr, version):
    if not version:
        return
    _logger.info('Running pre-migration for version %s', version)

    cr.execute("""
        ALTER TABLE my_model
        RENAME COLUMN old_name TO new_name
    """)

    cr.execute("""
        ALTER TABLE my_model
        ADD COLUMN IF NOT EXISTS new_field VARCHAR(255) DEFAULT 'draft'
    """)
```

### Post-Migration (after module update)

```python
# migrations/18.0.1.0.1/post-migrate.py
from odoo import api, SUPERUSER_ID

def migrate(cr, version):
    if not version:
        return
    env = api.Environment(cr, SUPERUSER_ID, {})

    # Recompute stored computed field
    records = env['my.model'].search([])
    records._compute_total_amount()

    # Data transformation
    cr.execute("""
        UPDATE my_model SET category = 'type_a'
        WHERE old_category IN ('cat1', 'cat2')
    """)
```

---

## Best Practices

1. **Security first** - Load security files before views in manifest
2. **Record rules with noupdate** - Use `noupdate="1"` for record rules
3. **_inherit for extension** - Most common inheritance pattern
4. **AbstractModel for mixins** - Reusable fields without database tables
5. **Cron batch processing** - Commit per batch for long-running jobs
6. **_check_company_auto** - Enable automatic company validation
7. **Multi-currency _convert** - Use currency._convert for exchange rates
8. **State machine validation** - Always validate transitions explicitly
9. **Migration pre/post split** - Rename columns pre-migration, transform data post-migration

---

## Anti-Patterns

- Missing `noupdate="1"` on record rules (overwritten on module update)
- Using `sudo()` without documenting the security bypass reason
- Cron jobs without batch processing (memory issues on large datasets)
- Missing `_check_company_auto` on multi-company models
- Direct SQL without using migration scripts (breaks upgrade path)
- Not using `ensure_one()` in action methods
- Hardcoding company/user IDs instead of using `self.env`

---

## Sources & References

- [Security Access Control - FAIRCHANCE](https://fairchanceforcrm.com/odoo-access-control/)
- [Odoo Security Complete Guide](https://medium.com/@niralchaudhary9/odoo-security-complete-guide-to-access-rights-record-rules-field-level-security-e0e3c878f08f)
- [Security in Odoo - Odoo 18](https://www.odoo.com/documentation/18.0/developer/reference/backend/security.html)
- [Inheritance - Odoo 18](https://www.odoo.com/documentation/18.0/developer/tutorials/server_framework_101/12_inheritance.html)
- [Creating Scheduled Actions](https://www.braincuber.com/tutorial/creating-scheduled-actions-cron-jobs-odoo-complete-guide)
- [Upgrade Scripts - Odoo 18](https://www.odoo.com/documentation/18.0/developer/reference/upgrades/upgrade_scripts.html)
- [External JSON-2 API - Odoo 19](https://www.odoo.com/documentation/19.0/developer/reference/external_api.html)
- [Multi-Company Guidelines - Odoo 18](https://www.odoo.com/documentation/18.0/developer/howtos/company.html)
