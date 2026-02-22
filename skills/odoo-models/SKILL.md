---
name: odoo-models
description: Odoo ORM patterns — field types, computed fields, constraints, CRUD overrides, recordset operations, batch processing, prefetch optimization, read_group aggregations
---

# Odoo Models & ORM Patterns

Staff-engineer-level Odoo 17/18 ORM patterns. Covers field types and options, computed fields, constraints (Python and SQL), CRUD overrides, recordset operations, batch processing, prefetch optimization, read_group aggregations, domain filters, and state machines.

## Table of Contents

1. [Module Structure](#module-structure)
2. [Field Types and Options](#field-types-and-options)
3. [Computed Fields](#computed-fields)
4. [Constraints](#constraints)
5. [CRUD Overrides](#crud-overrides)
6. [Recordset Operations](#recordset-operations)
7. [Prefetch Optimization](#prefetch-optimization)
8. [Read Group Aggregations](#read-group-aggregations)
9. [State Machine Pattern](#state-machine-pattern)
10. [Best Practices](#best-practices)
11. [Anti-Patterns](#anti-patterns)

---

## Module Structure

```
my_module/
├── __init__.py
├── __manifest__.py
├── models/
│   ├── __init__.py
│   └── my_model.py
├── views/
│   ├── my_model_views.xml
│   └── menu_items.xml
├── security/
│   ├── ir.model.access.csv
│   ├── security_groups.xml
│   └── record_rules.xml
├── data/
│   └── initial_data.xml
├── wizards/
│   ├── __init__.py
│   └── my_wizard.py
├── migrations/
│   └── 18.0.1.0.1/
│       ├── pre-migrate.py
│       └── post-migrate.py
└── tests/
    ├── __init__.py
    └── test_my_model.py
```

### Manifest Best Practices

```python
{
    'name': 'My Module',
    'version': '18.0.1.0.0',  # Odoo version + module version
    'category': 'Tools',
    'summary': 'Concise one-line description',
    'author': 'Your Company',
    'license': 'LGPL-3',

    # Dependencies
    'depends': ['base', 'mail', 'web'],

    # External dependencies
    'external_dependencies': {
        'python': ['requests', 'pandas'],
        'bin': ['wkhtmltopdf'],
    },

    # Data files (order matters!)
    'data': [
        # Security first
        'security/security_groups.xml',
        'security/ir.model.access.csv',
        'security/record_rules.xml',
        # Data files
        'data/initial_data.xml',
        # Views
        'views/my_model_views.xml',
        'views/menu_items.xml',
    ],

    # JS/CSS assets
    'assets': {
        'web.assets_backend': [
            'my_module/static/src/js/**/*',
            'my_module/static/src/xml/**/*',
        ],
    },

    'installable': True,
    'application': True,
}
```

---

## Field Types and Options

```python
from odoo import api, fields, models, _
from odoo.exceptions import ValidationError, UserError

class AdvancedModel(models.Model):
    _name = 'advanced.model'
    _description = 'Advanced ORM Patterns'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'sequence, name'
    _rec_name = 'display_name'

    # Basic fields
    name = fields.Char(
        string='Name',
        required=True,
        index=True,        # Database index for performance
        tracking=True,     # Track changes in chatter
        translate=True,    # Multi-language support
    )

    sequence = fields.Integer(default=10, index=True)
    active = fields.Boolean(default=True)  # Enable archive

    # State machine
    state = fields.Selection([
        ('draft', 'Draft'),
        ('submitted', 'Submitted'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
        ('done', 'Done'),
    ], default='draft', required=True, tracking=True)

    # Relational fields
    partner_id = fields.Many2one(
        'res.partner',
        string='Partner',
        ondelete='restrict',  # cascade, set null, restrict
        index=True,
        tracking=True,
    )

    company_id = fields.Many2one(
        'res.company',
        string='Company',
        required=True,
        default=lambda self: self.env.company,
    )

    line_ids = fields.One2many(
        'advanced.model.line',
        'parent_id',
        string='Lines',
    )

    tag_ids = fields.Many2many(
        'advanced.tag',
        'advanced_model_tag_rel',  # Explicit relation table
        'model_id',
        'tag_id',
        string='Tags',
    )

    # Company-dependent field (different values per company)
    default_warehouse_id = fields.Many2one(
        'stock.warehouse',
        company_dependent=True,
    )
```

---

## Computed Fields

```python
    # Stored computed field (optimized)
    total_amount = fields.Float(
        compute='_compute_total_amount',
        store=True,
        tracking=True,
    )

    @api.depends('line_ids.amount', 'line_ids.quantity')
    def _compute_total_amount(self):
        """
        Staff pattern: Always batch compute, never loop unnecessarily.
        Use read_group for aggregations when possible.
        """
        for record in self:
            record.total_amount = sum(
                line.amount * line.quantity
                for line in record.line_ids
            )

    # Related field (shortcut to partner field)
    partner_email = fields.Char(
        related='partner_id.email',
        string='Partner Email',
        store=True,    # Store for search/group_by
        readonly=True,
    )

    # Non-stored computed field (dynamic)
    display_name = fields.Char(
        compute='_compute_display_name',
        store=False,
    )

    @api.depends('name', 'sequence')
    def _compute_display_name(self):
        for record in self:
            record.display_name = f"[{record.sequence}] {record.name}"

    # Onchange for UI hints only
    @api.onchange('partner_id')
    def _onchange_partner_id(self):
        """
        Staff pattern: Use onchange for UI hints only.
        Never use for business logic (use computed fields instead).
        """
        if self.partner_id:
            self.partner_email = self.partner_id.email
            if not self.partner_id.active:
                return {
                    'warning': {
                        'title': _('Warning'),
                        'message': _('Selected partner is archived.'),
                    }
                }
```

---

## Constraints

```python
    # Python constraint
    @api.constrains('name', 'company_id')
    def _check_name_unique_per_company(self):
        for record in self:
            domain = [
                ('name', '=', record.name),
                ('company_id', '=', record.company_id.id),
                ('id', '!=', record.id),
            ]
            if self.search_count(domain) > 0:
                raise ValidationError(_(
                    'Name must be unique per company.'
                ))

    # SQL constraint
    _sql_constraints = [
        (
            'sequence_positive',
            'CHECK(sequence > 0)',
            'Sequence must be positive.'
        ),
        (
            'unique_name_company',
            'UNIQUE(name, company_id)',
            'Name must be unique per company.'
        ),
    ]
```

---

## CRUD Overrides

```python
    @api.model
    def create(self, vals):
        """Staff pattern: Validate and enrich data on create."""
        if not vals.get('sequence'):
            vals['sequence'] = self.search_count([]) + 1

        record = super().create(vals)
        record._post_create_hook()
        return record

    def write(self, vals):
        """Staff pattern: Track changes and trigger workflows."""
        if 'state' in vals:
            self._validate_state_transition(vals['state'])

        result = super().write(vals)

        if 'partner_id' in vals:
            self._update_related_records()

        return result

    def unlink(self):
        """Staff pattern: Prevent deletion if conditions met."""
        if any(rec.state not in ['draft', 'rejected'] for rec in self):
            raise UserError(_(
                'Cannot delete records in state other than Draft or Rejected.'
            ))
        return super().unlink()

    # Search and domain patterns
    def _get_domain_for_pending(self):
        """Staff pattern: Build complex domains programmatically."""
        return [
            '&',
            ('state', 'in', ['draft', 'submitted']),
            '|',
                ('partner_id.active', '=', True),
                ('partner_id', '=', False),
        ]
```

---

## Recordset Operations

```python
    def batch_update_state(self, new_state):
        """
        Staff pattern: Always batch operations, never loop with write().
        One write() call for entire recordset.
        """
        # BAD: for record in self: record.state = new_state
        # GOOD:
        self.write({'state': new_state})

    def action_submit(self):
        """Button action with state transition."""
        self.ensure_one()
        if self.state != 'draft':
            raise UserError(_('Only draft records can be submitted.'))

        self.write({'state': 'submitted'})

        # Post message to chatter
        self.message_post(
            body=_('Record submitted for approval.'),
            message_type='notification',
        )

        # Create activity for approval
        self.activity_schedule(
            'my_module.mail_activity_type_approval',
            user_id=self.env.ref('base.group_system').users[0].id,
            summary=_('Approval Required'),
        )
```

---

## Prefetch Optimization

```python
class PrefetchOptimization(models.Model):
    _name = 'prefetch.example'

    def prefetch_pattern_correct(self):
        """
        Staff pattern: Trigger prefetch before loop.
        Odoo prefetches ~1000 records at a time.
        """
        records = self.search([('active', '=', True)])

        # Trigger prefetch for relational fields
        records.mapped('partner_id')
        records.mapped('line_ids.product_id')

        # Now loop without N+1 queries
        for record in records:
            print(record.partner_id.name)
            for line in record.line_ids:
                print(line.product_id.name)

    def process_in_batches(self):
        """Staff pattern: Process large datasets in batches."""
        batch_size = 500
        offset = 0

        while True:
            records = self.search(
                [],
                limit=batch_size,
                offset=offset,
                order='id',
            )

            if not records:
                break

            records._process_batch()
            self.env.cr.commit()  # Commit per batch (long-running jobs)
            offset += batch_size

    def complex_transaction(self):
        """Staff pattern: Manage cache and database sync."""
        records = self.create([{'name': f'Rec {i}'} for i in range(100)])

        # Force write to database (before raw SQL)
        self.env.flush_all()

        self.env.cr.execute("""
            UPDATE prefetch_example
            SET sequence = sequence + 1
            WHERE id IN %s
        """, (tuple(records.ids),))

        # Invalidate cache (force reload from DB)
        records.invalidate_recordset(['sequence'])
```

---

## Read Group Aggregations

```python
    def get_totals_by_partner(self):
        """
        Staff pattern: Use read_group instead of Python loops.
        Executes efficient SQL GROUP BY.
        """
        # BAD: Python aggregation
        # totals = {}
        # for record in self.search([]):
        #     totals[record.partner_id] = totals.get(...) + record.amount

        # GOOD: SQL aggregation
        result = self.read_group(
            domain=[],
            fields=['partner_id', 'amount:sum'],
            groupby=['partner_id'],
            orderby='amount desc',
        )
        return result
```

---

## State Machine Pattern

```python
    def _validate_state_transition(self, new_state):
        """Staff pattern: Validate state machine transitions."""
        allowed_transitions = {
            'draft': ['submitted'],
            'submitted': ['approved', 'rejected'],
            'approved': ['done'],
            'rejected': ['draft'],
            'done': [],
        }

        for record in self:
            if new_state not in allowed_transitions.get(record.state, []):
                raise UserError(_(
                    'Cannot transition from %(from)s to %(to)s.',
                    from_=record.state,
                    to=new_state,
                ))
```

---

## Best Practices

1. **Batch create/write** - Single `create(vals_list)` or `write()` call for entire recordset
2. **Prefetch before loops** - Use `mapped()` to trigger prefetch, avoid N+1 queries
3. **read_group for aggregations** - SQL GROUP BY instead of Python loops
4. **Store computed fields** - Use `store=True` for fields used in search/group_by
5. **Explicit relation tables** - Name Many2many relation tables explicitly
6. **Index frequently searched fields** - Use `index=True` on fields used in domains
7. **Flush before raw SQL** - Call `self.env.flush_all()` before `cr.execute()`
8. **Invalidate after raw SQL** - Call `invalidate_recordset()` after direct SQL updates
9. **Use sudo() sparingly** - Document why bypass is needed, limit scope
10. **State validation** - Always validate state transitions in write()

---

## Anti-Patterns

- Looping with individual `write()` calls instead of batch write
- Accessing relational fields in loops without prefetch (N+1 queries)
- Using Python loops for aggregation instead of `read_group`
- Using `onchange` for business logic (use computed fields instead)
- Direct SQL without `flush_all()` first (stale cache)
- Missing `ondelete` on Many2one fields (defaults to `set null`)
- Not using `ensure_one()` before accessing fields on action methods
- Bypassing access rules with `sudo()` without documenting the reason

---

## Sources & References

- [ORM API - Odoo 18 Documentation](https://docs.advanceinsight.dev/developer/reference/backend/orm.html)
- [Computed Fields and Onchanges - Odoo 18](https://www.odoo.com/documentation/18.0/developer/tutorials/server_framework_101/08_compute_onchange.html)
- [Odoo ORM Performance Expert Tips](https://4devnet.com/odoo-orm-performance-expert-tips-for-faster-cleaner-code/)
- [Performance Optimization - Odoo 18](https://www.odoo.com/documentation/18.0/developer/reference/backend/performance.html)
- [Prefetch Patterns - Odoo 17](https://www.cybrosys.com/odoo/odoo-books/odoo-17-development/performance-optimisation/)
- [Module Manifests - Odoo 19](https://www.odoo.com/documentation/19.0/developer/reference/backend/module.html)
