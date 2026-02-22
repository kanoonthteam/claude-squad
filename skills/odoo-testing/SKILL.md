---
name: odoo-testing
description: Odoo testing patterns — TransactionCase, Form class UI simulation, HttpCase with browser tours, test tags, access rights testing, database indexes, SQL views for reporting
---

# Odoo Testing & Performance

Staff-engineer-level Odoo 17/18 testing and performance patterns. Covers TransactionCase for model testing, Form class for UI simulation, HttpCase with browser tours, test tags and organization, access rights testing, database indexes, SQL views for reporting, and profiling techniques.

## Table of Contents

1. [TransactionCase](#transactioncase)
2. [Form Class Testing](#form-class-testing)
3. [HttpCase & Tour Testing](#httpcase--tour-testing)
4. [Access Rights Testing](#access-rights-testing)
5. [Database Indexes](#database-indexes)
6. [SQL Views for Reporting](#sql-views-for-reporting)
7. [Profiling](#profiling)
8. [Best Practices](#best-practices)
9. [Anti-Patterns](#anti-patterns)

---

## TransactionCase

Each test runs in a transaction with savepoint that is rolled back after the test.

```python
from odoo.tests.common import TransactionCase
from odoo.exceptions import ValidationError, UserError

class TestMyModel(TransactionCase):
    """
    Staff pattern: TransactionCase for model testing.
    Each test runs in a transaction with savepoint.
    """

    @classmethod
    def setUpClass(cls):
        """Set up test data once for all tests."""
        super().setUpClass()

        cls.partner = cls.env['res.partner'].create({
            'name': 'Test Partner',
            'email': 'test@example.com',
        })

        cls.Model = cls.env['my.model']

    def setUp(self):
        """Set up before each test."""
        super().setUp()

        self.record = self.Model.create({
            'name': 'Test Record',
            'partner_id': self.partner.id,
        })

    def test_create_record(self):
        """Test record creation."""
        record = self.Model.create({
            'name': 'New Record',
            'partner_id': self.partner.id,
        })

        self.assertTrue(record)
        self.assertEqual(record.state, 'draft')
        self.assertEqual(record.partner_id, self.partner)

    def test_computed_field(self):
        """Test computed field calculation."""
        self.env['my.model.line'].create({
            'parent_id': self.record.id,
            'quantity': 2,
            'amount': 50.0,
        })

        self.assertEqual(self.record.total_amount, 100.0)

    def test_constraint_validation(self):
        """Test constraint raises error."""
        with self.assertRaises(ValidationError):
            self.record.write({'name': 'ab'})  # Too short

    def test_state_transition(self):
        """Test state machine."""
        self.record.action_submit()
        self.assertEqual(self.record.state, 'submitted')

        # Invalid transition should fail
        with self.assertRaises(UserError):
            self.record.action_submit()

    def test_unlink_protection(self):
        """Test deletion protection."""
        self.record.action_submit()

        with self.assertRaises(UserError):
            self.record.unlink()

    def test_batch_operations(self):
        """Test batch processing."""
        records = self.Model.create([
            {'name': f'Batch {i}', 'partner_id': self.partner.id}
            for i in range(10)
        ])

        self.assertEqual(len(records), 10)

        # Batch state update
        records.batch_update_state('submitted')

        for record in records:
            self.assertEqual(record.state, 'submitted')
```

---

## Form Class Testing

The Form class simulates UI interaction, testing onchange, computed fields, and required field validation.

```python
from odoo.tests.common import Form

class TestMyModelForm(TransactionCase):
    """
    Staff pattern: Form class tests simulate UI interaction.
    Tests onchange, computed fields, required fields.
    """

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.partner = cls.env['res.partner'].create({
            'name': 'Test Partner',
            'email': 'partner@test.com',
        })

    def test_onchange_partner(self):
        """Test onchange method."""
        with Form(self.env['my.model']) as form:
            form.name = 'Test'
            form.partner_id = self.partner

            # Onchange should populate email
            self.assertEqual(form.partner_email, self.partner.email)

    def test_required_field_validation(self):
        """Test required field validation."""
        with self.assertRaises(Exception):
            with Form(self.env['my.model']) as form:
                # Missing required 'name' field
                form.partner_id = self.partner
                form.save()

    def test_one2many_lines(self):
        """Test O2M line manipulation."""
        with Form(self.env['my.model']) as form:
            form.name = 'Test'

            # Add lines
            with form.line_ids.new() as line:
                line.product_id = self.env.ref('product.product_product_1')
                line.quantity = 2
                line.amount = 50.0

            with form.line_ids.new() as line:
                line.product_id = self.env.ref('product.product_product_2')
                line.quantity = 1
                line.amount = 100.0

            record = form.save()

        self.assertEqual(len(record.line_ids), 2)
        self.assertEqual(record.total_amount, 200.0)

    def test_default_values(self):
        """Test default values are set correctly."""
        with Form(self.env['my.model']) as form:
            self.assertEqual(form.state, 'draft')
            self.assertTrue(form.active)

    def test_wizard_form(self):
        """Test wizard with Form class."""
        with Form(self.env['my.wizard']) as wizard_form:
            wizard_form.partner_id = self.partner
            wizard_form.date_from = '2024-01-01'
            wizard_form.date_to = '2024-12-31'
            wizard = wizard_form.save()

        result = wizard.action_confirm()
        self.assertIsNotNone(result)
```

---

## HttpCase & Tour Testing

HttpCase tests full user flows in the browser with guided tours.

```python
from odoo.tests.common import HttpCase
from odoo.tests import tagged

@tagged('post_install', '-at_install')
class TestMyModelTour(HttpCase):
    """
    Staff pattern: HttpCase for integration/tour testing.
    Tests full user flows in the browser.
    """

    def test_my_model_tour(self):
        """Test complete user tour."""
        self.start_tour("/web", 'my_model_tour', login='admin')
```

### Tour Definition (JavaScript)

```javascript
/** @odoo-module **/

import { registry } from "@web/core/registry";

registry.category("web_tour.tours").add("my_model_tour", {
    test: true,
    url: "/web",
    steps: () => [
        {
            content: "Open My Model menu",
            trigger: 'a[data-menu-xmlid="my_module.menu_my_model"]',
        },
        {
            content: "Create new record",
            trigger: 'button.o_list_button_add',
        },
        {
            content: "Fill name",
            trigger: 'input[name="name"]',
            run: "text Test Record",
        },
        {
            content: "Select partner",
            trigger: 'div[name="partner_id"] input',
            run: "text Azure",
        },
        {
            content: "Select first partner",
            trigger: '.ui-autocomplete > li > a:contains("Azure")',
        },
        {
            content: "Save record",
            trigger: 'button.o_form_button_save',
        },
        {
            content: "Submit record",
            trigger: 'button[name="action_submit"]',
        },
        {
            content: "Verify state",
            trigger: 'span.badge:contains("Submitted")',
            run: () => {},
        },
    ],
});
```

---

## Access Rights Testing

```python
class TestAccessRights(TransactionCase):
    """Test security access control."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        cls.user_basic = cls.env['res.users'].create({
            'name': 'Basic User',
            'login': 'basic_user',
            'groups_id': [(6, 0, [cls.env.ref('base.group_user').id])],
        })

        cls.user_manager = cls.env['res.users'].create({
            'name': 'Manager User',
            'login': 'manager_user',
            'groups_id': [(6, 0, [
                cls.env.ref('base.group_user').id,
                cls.env.ref('my_module.group_my_module_manager').id,
            ])],
        })

    def test_user_cannot_delete(self):
        """Basic user should not be able to delete records."""
        record = self.env['my.model'].create({
            'name': 'Test',
            'partner_id': self.env.ref('base.res_partner_1').id,
        })

        record_as_user = record.with_user(self.user_basic)

        with self.assertRaises(Exception):
            record_as_user.unlink()

    def test_manager_can_delete(self):
        """Manager should be able to delete draft records."""
        record = self.env['my.model'].create({
            'name': 'Test',
            'partner_id': self.env.ref('base.res_partner_1').id,
        })

        record_as_manager = record.with_user(self.user_manager)
        record_as_manager.unlink()  # Should not raise

    def test_record_rule_own_records(self):
        """User should only see own records."""
        # Create records as different users
        record_user1 = self.env['my.model'].with_user(self.user_basic).create({
            'name': 'User1 Record',
        })

        record_user2 = self.env['my.model'].with_user(self.user_manager).create({
            'name': 'Manager Record',
        })

        # Basic user should only see own records
        visible = self.env['my.model'].with_user(self.user_basic).search([])
        self.assertIn(record_user1, visible)
        # Manager record visibility depends on record rules

    def test_field_level_security(self):
        """Test field-level group restrictions."""
        record = self.env['my.model'].create({
            'name': 'Test',
            'secret_field': 'Hidden Value',
        })

        record_as_user = record.with_user(self.user_basic)

        # Basic user should not see manager-only fields
        data = record_as_user.read(['name', 'secret_field'])
        # Field is filtered based on groups attribute
```

---

## Database Indexes

```python
class IndexedModel(models.Model):
    _name = 'indexed.model'

    # Single column index
    reference = fields.Char(index=True)

    # Composite index via SQL
    _sql_constraints = [
        ('idx_company_reference', 'UNIQUE(company_id, reference)',
         'Reference must be unique per company'),
    ]

    def init(self):
        """Create database indexes on module install/upgrade."""
        super().init()

        # Partial index for active records only
        self.env.cr.execute("""
            CREATE INDEX IF NOT EXISTS idx_indexed_model_company_state
            ON indexed_model (company_id, state)
            WHERE active = true
        """)
```

---

## SQL Views for Reporting

```python
from odoo import tools

class ReportSQL(models.Model):
    _name = 'report.sales.summary'
    _description = 'Sales Summary Report'
    _auto = False  # Don't create table automatically
    _rec_name = 'partner_id'

    partner_id = fields.Many2one('res.partner', readonly=True)
    total_sales = fields.Float(readonly=True)
    order_count = fields.Integer(readonly=True)

    def init(self):
        """Create SQL view for fast reporting."""
        tools.drop_view_if_exists(self.env.cr, self._table)

        self.env.cr.execute(f"""
            CREATE OR REPLACE VIEW {self._table} AS (
                SELECT
                    ROW_NUMBER() OVER (ORDER BY partner_id) AS id,
                    partner_id,
                    SUM(amount_total) AS total_sales,
                    COUNT(*) AS order_count
                FROM
                    sale_order
                WHERE
                    state IN ('sale', 'done')
                GROUP BY
                    partner_id
            )
        """)
```

---

## Profiling

```python
import logging
from contextlib import contextmanager
import time

_logger = logging.getLogger(__name__)

class ProfiledModel(models.Model):
    _name = 'profiled.model'

    @contextmanager
    def _profile(self, operation_name):
        """Staff pattern: Profile operation performance."""
        start = time.time()
        start_queries = self.env.cr._obj.queries if hasattr(self.env.cr._obj, 'queries') else 0

        yield

        duration = time.time() - start
        end_queries = self.env.cr._obj.queries if hasattr(self.env.cr._obj, 'queries') else 0
        query_count = end_queries - start_queries

        _logger.info(
            f"{operation_name}: {duration:.2f}s, {query_count} queries"
        )

    def expensive_operation(self):
        """Profile this operation."""
        with self._profile('expensive_operation'):
            self.search([]).mapped('partner_id.name')
```

---

## Best Practices

1. **setUpClass for shared data** - Create test data once, not per test
2. **Form class for UI tests** - Simulates onchange and computed fields
3. **HttpCase for tours** - Test complete user flows in the browser
4. **Test state transitions** - Both valid and invalid transitions
5. **Test access rights** - Use `with_user()` to test different permission levels
6. **Test constraints** - Both Python `@api.constrains` and SQL constraints
7. **@tagged for test selection** - Use `post_install`, `-at_install` for tour tests
8. **SQL views with _auto = False** - For reporting models that aggregate data
9. **Partial indexes** - Index only active records with WHERE clause
10. **Profile with query count** - Track both time and number of SQL queries

---

## Anti-Patterns

- Creating test data in every test method instead of setUpClass
- Not testing access rights with different user contexts
- Missing constraint validation tests (only testing happy path)
- Tour tests without the `@tagged('post_install', '-at_install')` decorator
- Not using Form class for onchange testing (testing onchange directly)
- SQL views without ROW_NUMBER for id (breaks Odoo ORM compatibility)
- Missing `tools.drop_view_if_exists()` before CREATE VIEW
- Not profiling query counts in performance-critical operations

---

## Sources & References

- [Testing Odoo - Odoo 18](https://www.odoo.com/documentation/18.0/developer/reference/backend/testing.html)
- [Performance Optimization - Odoo 18](https://www.odoo.com/documentation/18.0/developer/reference/backend/performance.html)
- [Prefetch Patterns - Odoo 17](https://www.cybrosys.com/odoo/odoo-books/odoo-17-development/performance-optimisation/)
- [OWL Lifecycle Hooks](https://pysquad.com/blogs/understanding-owl-lifecycle-hooks-in-odoo-17)
- [Multi-Step Wizards Tutorial](https://www.braincuber.com/tutorial/creating-multi-step-wizard-forms-odoo-complete-tutorial)
- [Odoo API Integration Guide](https://www.getknit.dev/blog/odoo-api-integration-guide-in-depth)
